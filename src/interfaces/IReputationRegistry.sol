// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IReputationRegistry
/// @notice Interface for the ERC-8004 Reputation Registry — a standardised feedback layer
///         where clients submit structured signals about agent performance.
/// @dev Reference: https://eips.ethereum.org/EIPS/eip-8004
interface IReputationRegistry {
    // ─── Write ───────────────────────────────────────────────────────────

    /// @notice Submit feedback for an agent.
    /// @param agentId       Target agent's ERC-8004 token ID.
    /// @param value         Signed fixed-point score (e.g. 500 with decimals=2 → 5.00).
    /// @param valueDecimals Number of decimal places in `value` (0-18).
    /// @param tag1          Primary category tag (e.g. "accuracy", "speed").
    /// @param tag2          Secondary category tag.
    /// @param endpoint      The agent endpoint used during the interaction.
    /// @param feedbackURI   IPFS/HTTPS URI pointing to detailed feedback JSON.
    /// @param feedbackHash  keccak256 of the feedback content for integrity verification.
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;

    /// @notice Revoke a previously submitted feedback.
    /// @param agentId       Target agent's ERC-8004 token ID.
    /// @param feedbackIndex Index of the caller's feedback to revoke.
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;

    /// @notice Append a response to a feedback entry (agent owner can respond).
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external;

    // ─── Read ────────────────────────────────────────────────────────────

    /// @notice Aggregated summary for an agent, optionally filtered by clients and tags.
    /// @return count    Number of matching (non-revoked) feedback entries.
    /// @return value    Sum of feedback values.
    /// @return decimals Common decimal precision for the returned value.
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, int256 value, uint8 decimals);

    /// @notice Read a single feedback entry.
    function readFeedback(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    )
        external
        view
        returns (int128 value, uint8 decimals, string memory tag1, string memory tag2, bool isRevoked);

    /// @notice Read all feedback entries matching the given filters.
    function readAllFeedback(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    )
        external
        view
        returns (
            address[] memory clients,
            uint64[] memory indexes,
            int128[] memory values,
            uint8[] memory decimals,
            string[] memory tag1s,
            string[] memory tag2s,
            bool[] memory revoked
        );

    /// @notice Get the last feedback index submitted by a client for an agent.
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);
}
