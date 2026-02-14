// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReputationRegistry} from "./interfaces/IReputationRegistry.sol";
import {AgentFactory} from "./AgentFactory.sol";

/// @title AgentRating
/// @author ClawNad
/// @notice Convenience wrapper around the ERC-8004 Reputation Registry that validates inputs,
///         enforces score bounds, and emits a ClawNad-specific event for indexing.
/// @dev Decoupled from the factory for minimal surface area. The underlying ERC-8004 registry
///      already prevents agent owners from rating their own agents.
///
///      IMPORTANT: On the Reputation Registry, msg.sender is this contract (not the end user).
///      The original rater's address is captured in the `AgentRated` event only. Off-chain
///      indexers should use the event's `rater` field to attribute ratings to users.
contract AgentRating {
    // ═══════════════════════════════════════════════════════════════════════
    //                              ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error AgentRating__AgentNotActive(uint256 agentId);
    error AgentRating__ScoreOutOfRange(int128 score);
    error AgentRating__EmptyTag();
    error AgentRating__ZeroAddress();

    // ═══════════════════════════════════════════════════════════════════════
    //                              EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a user rates an agent through this contract.
    /// @dev The ERC-8004 Reputation Registry also emits its own FeedbackGiven event.
    event AgentRated(
        uint256 indexed agentId, address indexed rater, int128 score, string tag1, string tag2, bytes32 feedbackHash
    );

    // ═══════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Score precision: 2 decimals (e.g., 500 = 5.00, 100 = 1.00).
    uint8 public constant VALUE_DECIMALS = 2;

    /// @notice Minimum allowed score: 1.00 (encoded as 100).
    int128 public constant MIN_SCORE = 100;

    /// @notice Maximum allowed score: 5.00 (encoded as 500).
    int128 public constant MAX_SCORE = 500;

    // ═══════════════════════════════════════════════════════════════════════
    //                           IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════

    IReputationRegistry public immutable reputationRegistry;
    AgentFactory public immutable factory;

    // ═══════════════════════════════════════════════════════════════════════
    //                           CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @param _reputationRegistry ERC-8004 Reputation Registry address.
    /// @param _factory            ClawNad AgentFactory address.
    constructor(address _reputationRegistry, address _factory) {
        if (_reputationRegistry == address(0)) revert AgentRating__ZeroAddress();
        if (_factory == address(0)) revert AgentRating__ZeroAddress();

        reputationRegistry = IReputationRegistry(_reputationRegistry);
        factory = AgentFactory(payable(_factory));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                         EXTERNAL — WRITE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Rate an agent after using its service.
    /// @dev Score uses 2 decimal places: 100 = 1.00 (worst) to 500 = 5.00 (best).
    ///      The ERC-8004 registry prevents the agent owner from rating their own agent.
    ///      NOTE: The reputation registry records this contract as the feedback submitter,
    ///      not the actual caller. Use the `AgentRated` event's `rater` field for attribution.
    /// @param agentId      The agent to rate.
    /// @param score        Rating value: 100-500 (1.00-5.00 with 2 decimals).
    /// @param tag1         Primary category tag (e.g., "accuracy", "speed", "reliability").
    /// @param tag2         Optional secondary tag (can be empty).
    /// @param feedbackURI  Optional IPFS/HTTPS URI to detailed feedback JSON.
    /// @param feedbackHash keccak256 hash of the feedback content (bytes32(0) if no URI).
    function rateAgent(
        uint256 agentId,
        int128 score,
        string calldata tag1,
        string calldata tag2,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external {
        // Validate
        if (score < MIN_SCORE || score > MAX_SCORE) revert AgentRating__ScoreOutOfRange(score);
        if (bytes(tag1).length == 0) revert AgentRating__EmptyTag();

        AgentFactory.AgentInfo memory agent = factory.getAgent(agentId);
        if (!agent.active) revert AgentRating__AgentNotActive(agentId);

        // Submit to ERC-8004 Reputation Registry
        reputationRegistry.giveFeedback(agentId, score, VALUE_DECIMALS, tag1, tag2, agent.endpoint, feedbackURI, feedbackHash);

        emit AgentRated(agentId, msg.sender, score, tag1, tag2, feedbackHash);
    }
}
