// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReputationRegistry} from "../../src/interfaces/IReputationRegistry.sol";

/// @notice Minimal mock of the ERC-8004 Reputation Registry for testing.
contract MockReputationRegistry is IReputationRegistry {
    struct Feedback {
        int128 value;
        uint8 decimals;
        string tag1;
        string tag2;
        string endpoint;
        string feedbackURI;
        bytes32 feedbackHash;
        bool isRevoked;
    }

    // agentId => clientAddress => feedbacks
    mapping(uint256 => mapping(address => Feedback[])) internal _feedbacks;

    // agentId => (count, sumValue, decimals) for quick summary
    mapping(uint256 => uint64) public feedbackCount;
    mapping(uint256 => int256) public feedbackSum;

    event FeedbackGiven(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        int128 value,
        uint8 valueDecimals,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );

    event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex);

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external override {
        uint64 index = uint64(_feedbacks[agentId][msg.sender].length);

        _feedbacks[agentId][msg.sender].push(
            Feedback({
                value: value,
                decimals: valueDecimals,
                tag1: tag1,
                tag2: tag2,
                endpoint: endpoint,
                feedbackURI: feedbackURI,
                feedbackHash: feedbackHash,
                isRevoked: false
            })
        );

        feedbackCount[agentId]++;
        feedbackSum[agentId] += int256(value);

        emit FeedbackGiven(agentId, msg.sender, index, value, valueDecimals, tag1, tag2, endpoint, feedbackURI, feedbackHash);
    }

    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external override {
        Feedback storage fb = _feedbacks[agentId][msg.sender][feedbackIndex];
        require(!fb.isRevoked, "Already revoked");
        fb.isRevoked = true;
        feedbackCount[agentId]--;
        feedbackSum[agentId] -= int256(fb.value);

        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    function appendResponse(uint256, address, uint64, string calldata, bytes32) external pure override {
        // No-op in mock
    }

    function getSummary(
        uint256 agentId,
        address[] calldata,
        string calldata,
        string calldata
    ) external view override returns (uint64 count, int256 value, uint8 decimals) {
        return (feedbackCount[agentId], feedbackSum[agentId], 2);
    }

    function readFeedback(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    )
        external
        view
        override
        returns (int128 value, uint8 decimals, string memory tag1, string memory tag2, bool isRevoked)
    {
        Feedback memory fb = _feedbacks[agentId][clientAddress][feedbackIndex];
        return (fb.value, fb.decimals, fb.tag1, fb.tag2, fb.isRevoked);
    }

    function readAllFeedback(
        uint256,
        address[] calldata,
        string calldata,
        string calldata,
        bool
    )
        external
        pure
        override
        returns (
            address[] memory,
            uint64[] memory,
            int128[] memory,
            uint8[] memory,
            string[] memory,
            string[] memory,
            bool[] memory
        )
    {
        // Simplified mock — return empty arrays
        return (
            new address[](0),
            new uint64[](0),
            new int128[](0),
            new uint8[](0),
            new string[](0),
            new string[](0),
            new bool[](0)
        );
    }

    function getLastIndex(uint256 agentId, address clientAddress) external view override returns (uint64) {
        uint256 len = _feedbacks[agentId][clientAddress].length;
        return len == 0 ? 0 : uint64(len - 1);
    }
}
