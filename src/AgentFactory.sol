// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IIdentityRegistry, MetadataEntry} from "./interfaces/IIdentityRegistry.sol";
import {IReputationRegistry} from "./interfaces/IReputationRegistry.sol";
import {IBondingCurveRouter, TokenCreationParams, ILens} from "./interfaces/INadFun.sol";

/// @title AgentFactory
/// @author ClawNad
/// @notice One-click AI agent launchpad: registers an ERC-8004 identity, deploys a nad.fun token,
///         and links them together — all in a single transaction.
/// @dev The factory temporarily holds the ERC-8004 NFT during launch and immediately transfers it
///      to the caller. It implements IERC721Receiver to accept safe-minted NFTs.
contract AgentFactory is Ownable2Step, Pausable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error AgentFactory__AgentNotFound(uint256 agentId);
    error AgentFactory__NotAgentOwner(uint256 agentId, address caller);
    error AgentFactory__TokenAlreadyLinked(uint256 agentId);
    error AgentFactory__TokenAlreadyUsed(address token);
    error AgentFactory__AgentNotActive(uint256 agentId);
    error AgentFactory__AgentAlreadyActive(uint256 agentId);
    error AgentFactory__ZeroAddress();
    error AgentFactory__EmptyURI();
    error AgentFactory__EmptyName();
    error AgentFactory__EmptySymbol();
    error AgentFactory__NoTokenLinked(uint256 agentId);
    error AgentFactory__TokenNotFound(address token);
    error AgentFactory__MONTransferFailed();
    error AgentFactory__UnexpectedNFT(address operator);

    // ═══════════════════════════════════════════════════════════════════════
    //                              EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event AgentLaunched(
        uint256 indexed agentId,
        address indexed token,
        address indexed creator,
        string agentURI,
        string endpoint,
        string tokenName,
        string tokenSymbol
    );

    event AgentRegistered(uint256 indexed agentId, address indexed creator, string agentURI, string endpoint);

    event AgentTokenLinked(uint256 indexed agentId, address indexed token);

    event AgentEndpointUpdated(uint256 indexed agentId, string newEndpoint);

    event AgentWalletUpdated(uint256 indexed agentId, address newWallet);

    event AgentDeactivated(uint256 indexed agentId);

    event AgentReactivated(uint256 indexed agentId);

    // ═══════════════════════════════════════════════════════════════════════
    //                              TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice On-chain record linking an ERC-8004 agent to its nad.fun token and operational metadata.
    struct AgentInfo {
        uint256 agentId; // ERC-8004 NFT token ID
        address token; // nad.fun ERC-20 token (address(0) if none)
        address creator; // Original launcher
        address agentWallet; // Wallet that receives x402 revenue
        string endpoint; // Agent API base URL
        uint64 launchedAt; // block.timestamp of launch
        bool active; // Agent is operational
    }

    /// @notice Parameters for the one-click launch.
    struct LaunchParams {
        string agentURI; // IPFS/HTTPS URI → ERC-8004 registration JSON
        string endpoint; // Agent API base URL (x402-enabled)
        string tokenName; // ERC-20 name for nad.fun token
        string tokenSymbol; // ERC-20 symbol
        string tokenURI; // Metadata URI for nad.fun
        uint256 initialBuyAmount; // Tokens to buy on initial purchase (0 = none)
        bytes32 salt; // Salt from nad.fun API (POST /token/salt)
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                           IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════

    IIdentityRegistry public immutable identityRegistry;
    IReputationRegistry public immutable reputationRegistry;
    IBondingCurveRouter public immutable bondingCurveRouter;
    ILens public immutable lens;

    // ═══════════════════════════════════════════════════════════════════════
    //                             STORAGE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice agentId → full agent info.
    mapping(uint256 agentId => AgentInfo) internal _agents;

    /// @notice Reverse lookup: nad.fun token → agentId.
    /// @dev A value of 0 means "not linked". Since ERC-721 IDs from the identity registry start at 1,
    ///      this is safe. We also check `_agents[id].creator != address(0)` for existence.
    mapping(address token => uint256 agentId) public tokenToAgent;

    /// @notice Creator → list of agentIds they launched.
    mapping(address creator => uint256[] agentIds) internal _creatorAgents;

    /// @notice Total number of agents launched through this factory.
    uint256 public totalAgents;

    // ═══════════════════════════════════════════════════════════════════════
    //                           CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @param _identityRegistry   ERC-8004 Identity Registry address.
    /// @param _reputationRegistry ERC-8004 Reputation Registry address.
    /// @param _bondingCurveRouter nad.fun Bonding Curve Router address.
    /// @param _lens               nad.fun Lens (read helper) address.
    /// @param _owner              Protocol admin (can pause/unpause).
    constructor(
        address _identityRegistry,
        address _reputationRegistry,
        address _bondingCurveRouter,
        address _lens,
        address _owner
    ) Ownable(_owner) {
        if (_identityRegistry == address(0)) revert AgentFactory__ZeroAddress();
        if (_reputationRegistry == address(0)) revert AgentFactory__ZeroAddress();
        if (_bondingCurveRouter == address(0)) revert AgentFactory__ZeroAddress();
        if (_lens == address(0)) revert AgentFactory__ZeroAddress();

        identityRegistry = IIdentityRegistry(_identityRegistry);
        reputationRegistry = IReputationRegistry(_reputationRegistry);
        bondingCurveRouter = IBondingCurveRouter(_bondingCurveRouter);
        lens = ILens(_lens);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                         EXTERNAL — WRITE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice One-click launch: register ERC-8004 identity + deploy nad.fun token + link them.
    /// @dev Requires msg.value to cover nad.fun's deploy fee (10 MON) plus any initial buy cost.
    ///      The ERC-8004 NFT is minted to this contract and immediately transferred to msg.sender.
    ///      Any tokens from an initial buy are also forwarded to msg.sender.
    ///      Excess MON is refunded.
    /// @param params Launch parameters (see LaunchParams struct).
    /// @return agentId The ERC-8004 agent ID.
    /// @return token   The deployed nad.fun token address.
    function launchAgent(LaunchParams calldata params)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 agentId, address token)
    {
        if (bytes(params.agentURI).length == 0) revert AgentFactory__EmptyURI();
        if (bytes(params.tokenName).length == 0) revert AgentFactory__EmptyName();
        if (bytes(params.tokenSymbol).length == 0) revert AgentFactory__EmptySymbol();

        // 1. Register on ERC-8004 — NFT minted to this contract
        agentId = _registerIdentity(params.agentURI, params.endpoint);

        // 2. Deploy token on nad.fun — forwards msg.value for deploy fee + optional initial buy
        uint256 balanceBefore = address(this).balance - msg.value;
        token = _createToken(agentId, params);
        uint256 balanceAfter = address(this).balance;

        // 3. Store agent record
        _agents[agentId] = AgentInfo({
            agentId: agentId,
            token: token,
            creator: msg.sender,
            agentWallet: msg.sender,
            endpoint: params.endpoint,
            launchedAt: uint64(block.timestamp),
            active: true
        });

        tokenToAgent[token] = agentId;
        _creatorAgents[msg.sender].push(agentId);
        unchecked {
            ++totalAgents;
        }

        // 4. Transfer ERC-8004 NFT to the caller
        identityRegistry.transferFrom(address(this), msg.sender, agentId);

        // 5. Forward any initially-purchased tokens to the caller
        if (params.initialBuyAmount > 0) {
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance > 0) {
                IERC20(token).safeTransfer(msg.sender, tokenBalance);
            }
        }

        // 6. Refund excess MON
        if (balanceAfter > balanceBefore) {
            _sendMON(msg.sender, balanceAfter - balanceBefore);
        }

        emit AgentLaunched(
            agentId, token, msg.sender, params.agentURI, params.endpoint, params.tokenName, params.tokenSymbol
        );
    }

    /// @notice Register an ERC-8004 identity only (no token). Useful when the creator already has
    ///         a nad.fun token or doesn't want one yet.
    /// @param agentURI IPFS/HTTPS URI to the agent registration JSON.
    /// @param endpoint Agent API base URL.
    /// @return agentId The ERC-8004 agent ID.
    function registerAgent(
        string calldata agentURI,
        string calldata endpoint
    ) external nonReentrant whenNotPaused returns (uint256 agentId) {
        if (bytes(agentURI).length == 0) revert AgentFactory__EmptyURI();

        agentId = _registerIdentity(agentURI, endpoint);

        _agents[agentId] = AgentInfo({
            agentId: agentId,
            token: address(0),
            creator: msg.sender,
            agentWallet: msg.sender,
            endpoint: endpoint,
            launchedAt: uint64(block.timestamp),
            active: true
        });

        _creatorAgents[msg.sender].push(agentId);
        unchecked {
            ++totalAgents;
        }

        // Transfer NFT to the caller
        identityRegistry.transferFrom(address(this), msg.sender, agentId);

        emit AgentRegistered(agentId, msg.sender, agentURI, endpoint);
    }

    /// @notice Link a pre-existing nad.fun token to a registered agent.
    /// @dev Caller must own the ERC-8004 NFT for the given agentId.
    /// @param agentId      The agent to link the token to.
    /// @param tokenAddress The nad.fun token to link.
    function linkToken(uint256 agentId, address tokenAddress) external {
        _requireAgentExists(agentId);

        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert AgentFactory__NotAgentOwner(agentId, msg.sender);
        }
        if (_agents[agentId].token != address(0)) {
            revert AgentFactory__TokenAlreadyLinked(agentId);
        }
        if (tokenToAgent[tokenAddress] != 0) {
            revert AgentFactory__TokenAlreadyUsed(tokenAddress);
        }
        if (tokenAddress == address(0)) revert AgentFactory__ZeroAddress();

        _agents[agentId].token = tokenAddress;
        tokenToAgent[tokenAddress] = agentId;

        emit AgentTokenLinked(agentId, tokenAddress);
    }

    /// @notice Update the agent's API endpoint stored in this factory.
    /// @dev The caller must own the ERC-8004 NFT. To update the agentURI on ERC-8004,
    ///      call `identityRegistry.setAgentURI()` directly (you own the NFT).
    function updateEndpoint(uint256 agentId, string calldata newEndpoint) external {
        _requireAgentExists(agentId);

        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert AgentFactory__NotAgentOwner(agentId, msg.sender);
        }

        _agents[agentId].endpoint = newEndpoint;

        emit AgentEndpointUpdated(agentId, newEndpoint);
    }

    /// @notice Update the wallet that receives x402 revenue for this agent.
    /// @dev Does NOT update the ERC-8004 agentWallet — do that via the identity registry.
    function updateAgentWallet(uint256 agentId, address newWallet) external {
        _requireAgentExists(agentId);

        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert AgentFactory__NotAgentOwner(agentId, msg.sender);
        }
        if (newWallet == address(0)) revert AgentFactory__ZeroAddress();

        _agents[agentId].agentWallet = newWallet;

        emit AgentWalletUpdated(agentId, newWallet);
    }

    /// @notice Deactivate an agent (mark as not operational).
    function deactivateAgent(uint256 agentId) external {
        _requireAgentExists(agentId);

        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert AgentFactory__NotAgentOwner(agentId, msg.sender);
        }
        if (!_agents[agentId].active) revert AgentFactory__AgentNotActive(agentId);

        _agents[agentId].active = false;

        emit AgentDeactivated(agentId);
    }

    /// @notice Reactivate a previously deactivated agent.
    function reactivateAgent(uint256 agentId) external {
        _requireAgentExists(agentId);

        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert AgentFactory__NotAgentOwner(agentId, msg.sender);
        }
        if (_agents[agentId].active) revert AgentFactory__AgentAlreadyActive(agentId);

        _agents[agentId].active = true;

        emit AgentReactivated(agentId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                         EXTERNAL — READ
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get full agent info by agentId.
    function getAgent(uint256 agentId) external view returns (AgentInfo memory) {
        _requireAgentExists(agentId);
        return _agents[agentId];
    }

    /// @notice Get agent info by its linked nad.fun token address.
    function getAgentByToken(address tokenAddress) external view returns (AgentInfo memory) {
        uint256 agentId = tokenToAgent[tokenAddress];
        if (agentId == 0 || _agents[agentId].creator == address(0)) {
            revert AgentFactory__TokenNotFound(tokenAddress);
        }
        return _agents[agentId];
    }

    /// @notice List all agentIds created by a given address.
    function getAgentsByCreator(address creator) external view returns (uint256[] memory) {
        return _creatorAgents[creator];
    }

    /// @notice Check whether an agent exists in this factory.
    function agentExists(uint256 agentId) external view returns (bool) {
        return _agents[agentId].creator != address(0);
    }

    /// @notice Check if a token is linked to any agent in this factory.
    function isAgentToken(address tokenAddress) external view returns (bool) {
        return tokenToAgent[tokenAddress] != 0;
    }

    /// @notice Get the bonding curve progress for an agent's token (0 → 1e18).
    function getTokenProgress(uint256 agentId) external view returns (uint256) {
        address token = _agents[agentId].token;
        if (token == address(0)) revert AgentFactory__NoTokenLinked(agentId);
        return lens.getProgress(token);
    }

    /// @notice Check if the agent's token has graduated to the DEX.
    function isTokenGraduated(uint256 agentId) external view returns (bool) {
        address token = _agents[agentId].token;
        if (token == address(0)) revert AgentFactory__NoTokenLinked(agentId);
        return lens.isGraduated(token);
    }

    /// @notice Get the agent's aggregated reputation from ERC-8004.
    function getAgentReputation(uint256 agentId)
        external
        view
        returns (uint64 count, int256 value, uint8 decimals)
    {
        address[] memory empty = new address[](0);
        return reputationRegistry.getSummary(agentId, empty, "", "");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                          ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Pause all launch/register operations. Does not affect reads or updates.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause operations.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                          ERC-721 RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Required to receive ERC-721 tokens via safeTransferFrom / safeMint.
    ///      Only accepts NFTs from the identity registry to prevent griefing.
    function onERC721Received(address, address, uint256, bytes calldata) external view override returns (bytes4) {
        if (msg.sender != address(identityRegistry)) revert AgentFactory__UnexpectedNFT(msg.sender);
        return IERC721Receiver.onERC721Received.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                          RECEIVE MON
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Accept MON refunds from nad.fun's bonding curve router.
    receive() external payable {}

    // ═══════════════════════════════════════════════════════════════════════
    //                          INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Register agent on ERC-8004 Identity Registry. The NFT is minted to this contract.
    function _registerIdentity(string calldata agentURI, string calldata endpoint) internal returns (uint256 agentId) {
        MetadataEntry[] memory metadata = new MetadataEntry[](1);
        metadata[0] = MetadataEntry({metadataKey: "endpoint", metadataValue: abi.encode(endpoint)});

        agentId = identityRegistry.register(agentURI, metadata);
    }

    /// @dev Create a nad.fun token via the bonding curve router.
    function _createToken(uint256 agentId, LaunchParams calldata params) internal returns (address token) {
        TokenCreationParams memory creationParams = TokenCreationParams({
            name: params.tokenName,
            symbol: params.tokenSymbol,
            tokenURI: params.tokenURI,
            amountOut: params.initialBuyAmount,
            salt: params.salt,
            actionId: 1
        });

        (token,) = bondingCurveRouter.create{value: msg.value}(creationParams);
    }

    /// @dev Revert if the agent was never registered in this factory.
    function _requireAgentExists(uint256 agentId) internal view {
        if (_agents[agentId].creator == address(0)) {
            revert AgentFactory__AgentNotFound(agentId);
        }
    }

    /// @dev Send MON to an address, reverting on failure.
    function _sendMON(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert AgentFactory__MONTransferFailed();
    }
}
