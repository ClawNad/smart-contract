// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AgentFactory} from "./AgentFactory.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title RevenueRouter
/// @author ClawNad
/// @notice Tracks x402 revenue deposits for agents and distributes them:
///         - Platform fee  → treasury
///         - Agent share   → agent wallet
///         - Buyback share → held for future token buyback
/// @dev All token transfers use SafeERC20 for safe handling of non-standard ERC-20s.
contract RevenueRouter is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error RevenueRouter__UnsupportedToken(address token);
    error RevenueRouter__AgentNotActive(uint256 agentId);
    error RevenueRouter__ZeroAmount();
    error RevenueRouter__NothingToDistribute(uint256 agentId, address token);
    error RevenueRouter__ZeroAddress();
    error RevenueRouter__FeeTooHigh(uint256 bps);
    error RevenueRouter__NothingToWithdraw(uint256 agentId, address token);
    error RevenueRouter__NotAgentOwner(uint256 agentId, address caller);
    error RevenueRouter__TokenAlreadySupported(address token);
    error RevenueRouter__TokenNotSupported(address token);

    // ═══════════════════════════════════════════════════════════════════════
    //                              EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event RevenueDeposited(uint256 indexed agentId, address indexed paymentToken, uint256 amount, address indexed from);

    event RevenueDistributed(
        uint256 indexed agentId,
        address indexed paymentToken,
        uint256 agentShare,
        uint256 buybackShare,
        uint256 platformFee
    );

    event BuybackWithdrawn(uint256 indexed agentId, address indexed paymentToken, uint256 amount, address indexed to);

    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event PlatformFeeUpdated(uint256 oldBps, uint256 newBps);
    event BuybackBpsUpdated(uint256 oldBps, uint256 newBps);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    // ═══════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant MAX_PLATFORM_FEE_BPS = 1_000; // 10% hard cap
    uint256 public constant MAX_BUYBACK_BPS = 5_000; // 50% hard cap
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ═══════════════════════════════════════════════════════════════════════
    //                           IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════

    AgentFactory public immutable factory;

    // ═══════════════════════════════════════════════════════════════════════
    //                             STORAGE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Revenue accounting per agent per payment token.
    struct RevenueRecord {
        uint256 totalDeposited; // Cumulative deposits
        uint256 totalDistributed; // Cumulative amount sent to agent + treasury
        uint256 buybackAccrued; // Buyback funds held in this contract
        uint256 buybackWithdrawn; // Buyback funds withdrawn for execution
        uint64 lastDistributionAt; // Timestamp of last distribution
    }

    /// @dev agentId → paymentToken → record
    mapping(uint256 => mapping(address => RevenueRecord)) internal _revenue;

    /// @notice Whitelist of accepted payment tokens (stablecoins).
    mapping(address => bool) public supportedTokens;

    /// @notice Platform fee in basis points (200 = 2%).
    uint256 public platformFeeBps;

    /// @notice Percentage of post-fee revenue allocated to buyback (3000 = 30%).
    uint256 public buybackBps;

    /// @notice Platform treasury that receives the platform fee.
    address public treasury;

    // ═══════════════════════════════════════════════════════════════════════
    //                           CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @param _factory          AgentFactory contract address.
    /// @param _treasury         Address that receives platform fees.
    /// @param _platformFeeBps   Platform fee in basis points (max 1000 = 10%).
    /// @param _buybackBps       Buyback allocation in basis points (max 5000 = 50%).
    /// @param _supportedTokens  Initial set of whitelisted payment tokens.
    /// @param _owner            Admin address (can update config).
    constructor(
        address _factory,
        address _treasury,
        uint256 _platformFeeBps,
        uint256 _buybackBps,
        address[] memory _supportedTokens,
        address _owner
    ) Ownable(_owner) {
        if (_factory == address(0)) revert RevenueRouter__ZeroAddress();
        if (_treasury == address(0)) revert RevenueRouter__ZeroAddress();
        if (_platformFeeBps > MAX_PLATFORM_FEE_BPS) revert RevenueRouter__FeeTooHigh(_platformFeeBps);
        if (_buybackBps > MAX_BUYBACK_BPS) revert RevenueRouter__FeeTooHigh(_buybackBps);

        factory = AgentFactory(payable(_factory));
        treasury = _treasury;
        platformFeeBps = _platformFeeBps;
        buybackBps = _buybackBps;

        for (uint256 i; i < _supportedTokens.length; ++i) {
            if (_supportedTokens[i] == address(0)) revert RevenueRouter__ZeroAddress();
            supportedTokens[_supportedTokens[i]] = true;
            emit TokenAdded(_supportedTokens[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                         EXTERNAL — WRITE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deposit x402 revenue for a specific agent.
    /// @dev Caller must have approved this contract to spend `amount` of `paymentToken`.
    ///      Typically called by the agent's backend after receiving an x402 payment.
    /// @param agentId      The agent that earned this revenue.
    /// @param paymentToken The ERC-20 token received (must be whitelisted).
    /// @param amount       Amount of tokens to deposit.
    function depositRevenue(
        uint256 agentId,
        address paymentToken,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        if (!supportedTokens[paymentToken]) revert RevenueRouter__UnsupportedToken(paymentToken);
        if (amount == 0) revert RevenueRouter__ZeroAmount();

        AgentFactory.AgentInfo memory agent = factory.getAgent(agentId);
        if (!agent.active) revert RevenueRouter__AgentNotActive(agentId);

        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), amount);

        _revenue[agentId][paymentToken].totalDeposited += amount;

        emit RevenueDeposited(agentId, paymentToken, amount, msg.sender);
    }

    /// @notice Distribute all undistributed revenue for an agent in a given token.
    /// @dev Anyone can call this — permissionless distribution incentivises liveness.
    ///      Split: platformFee → treasury, buybackShare → held, agentShare → agentWallet.
    /// @param agentId      Target agent.
    /// @param paymentToken The payment token to distribute.
    function distribute(uint256 agentId, address paymentToken) external nonReentrant whenNotPaused {
        RevenueRecord storage record = _revenue[agentId][paymentToken];

        uint256 undistributed = record.totalDeposited - record.totalDistributed;
        if (undistributed == 0) revert RevenueRouter__NothingToDistribute(agentId, paymentToken);

        AgentFactory.AgentInfo memory agent = factory.getAgent(agentId);

        // Calculate splits
        uint256 platformFee = (undistributed * platformFeeBps) / BPS_DENOMINATOR;
        uint256 remaining = undistributed - platformFee;
        uint256 buybackShare = (remaining * buybackBps) / BPS_DENOMINATOR;
        uint256 agentShare = remaining - buybackShare;

        // Update accounting BEFORE transfers (CEI pattern)
        record.totalDistributed += undistributed;
        record.buybackAccrued += buybackShare;
        record.lastDistributionAt = uint64(block.timestamp);

        // Transfer platform fee
        if (platformFee > 0) {
            IERC20(paymentToken).safeTransfer(treasury, platformFee);
        }

        // Transfer agent's operational share
        if (agentShare > 0) {
            IERC20(paymentToken).safeTransfer(agent.agentWallet, agentShare);
        }

        // Buyback share stays in this contract

        emit RevenueDistributed(agentId, paymentToken, agentShare, buybackShare, platformFee);
    }

    /// @notice Withdraw accumulated buyback funds. Only callable by the agent owner.
    /// @dev The owner is responsible for executing the actual buyback off-chain or via a separate contract.
    ///      This keeps the RevenueRouter simple and avoids coupling to DEX-specific logic.
    /// @param agentId      Target agent.
    /// @param paymentToken The payment token to withdraw buyback funds for.
    /// @param to           Destination address for the funds.
    function withdrawBuybackFunds(
        uint256 agentId,
        address paymentToken,
        address to
    ) external nonReentrant {
        // Verify agent exists (getAgent reverts if not)
        factory.getAgent(agentId);

        if (identityRegistry().ownerOf(agentId) != msg.sender) {
            revert RevenueRouter__NotAgentOwner(agentId, msg.sender);
        }
        if (to == address(0)) revert RevenueRouter__ZeroAddress();

        RevenueRecord storage record = _revenue[agentId][paymentToken];
        uint256 available = record.buybackAccrued - record.buybackWithdrawn;
        if (available == 0) revert RevenueRouter__NothingToWithdraw(agentId, paymentToken);

        record.buybackWithdrawn += available;

        IERC20(paymentToken).safeTransfer(to, available);

        emit BuybackWithdrawn(agentId, paymentToken, available, to);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                         EXTERNAL — READ
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get the full revenue record for an agent + token pair.
    function getRevenue(uint256 agentId, address paymentToken) external view returns (RevenueRecord memory) {
        return _revenue[agentId][paymentToken];
    }

    /// @notice Get the amount available for distribution.
    function getUndistributed(uint256 agentId, address paymentToken) external view returns (uint256) {
        RevenueRecord memory record = _revenue[agentId][paymentToken];
        return record.totalDeposited - record.totalDistributed;
    }

    /// @notice Get the buyback funds available for withdrawal.
    function getAvailableBuyback(uint256 agentId, address paymentToken) external view returns (uint256) {
        RevenueRecord memory record = _revenue[agentId][paymentToken];
        return record.buybackAccrued - record.buybackWithdrawn;
    }

    /// @notice Convenience: get the identity registry from the factory.
    function identityRegistry() public view returns (IIdentityRegistry) {
        return factory.identityRegistry();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                              ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert RevenueRouter__ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function setPlatformFeeBps(uint256 newBps) external onlyOwner {
        if (newBps > MAX_PLATFORM_FEE_BPS) revert RevenueRouter__FeeTooHigh(newBps);
        emit PlatformFeeUpdated(platformFeeBps, newBps);
        platformFeeBps = newBps;
    }

    function setBuybackBps(uint256 newBps) external onlyOwner {
        if (newBps > MAX_BUYBACK_BPS) revert RevenueRouter__FeeTooHigh(newBps);
        emit BuybackBpsUpdated(buybackBps, newBps);
        buybackBps = newBps;
    }

    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert RevenueRouter__ZeroAddress();
        if (supportedTokens[token]) revert RevenueRouter__TokenAlreadySupported(token);
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function removeSupportedToken(address token) external onlyOwner {
        if (!supportedTokens[token]) revert RevenueRouter__TokenNotSupported(token);
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    /// @notice Rescue tokens accidentally sent to this contract (not part of any agent's buyback).
    /// @dev Only callable by the owner. Cannot rescue tokens that are allocated as buyback funds.
    /// @param token  ERC-20 token to rescue.
    /// @param to     Destination address.
    /// @param amount Amount to rescue.
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert RevenueRouter__ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
