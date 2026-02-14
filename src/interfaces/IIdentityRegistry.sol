// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Metadata key-value pair for ERC-8004 agent registration.
struct MetadataEntry {
    string metadataKey;
    bytes metadataValue;
}

/// @title IIdentityRegistry
/// @notice Interface for the ERC-8004 Identity Registry — an ERC-721 registry that assigns each agent
///         a unique on-chain identifier with a URI pointing to its registration file.
/// @dev Reference: https://eips.ethereum.org/EIPS/eip-8004
interface IIdentityRegistry {
    // ─── Registration ────────────────────────────────────────────────────

    /// @notice Register a new agent with an agent URI and optional metadata.
    /// @param agentURI  IPFS or HTTPS URI to the agent's registration JSON.
    /// @param metadata  Array of key-value metadata entries to store on-chain.
    /// @return agentId  The minted ERC-721 token ID representing this agent.
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);

    /// @notice Register a new agent with only an agent URI (no metadata).
    function register(string calldata agentURI) external returns (uint256 agentId);

    /// @notice Register a new agent with no URI and no metadata.
    function register() external returns (uint256 agentId);

    // ─── URI Management ──────────────────────────────────────────────────

    /// @notice Update the agent URI (registration file pointer).
    /// @dev Only callable by the agent owner or approved operator.
    function setAgentURI(uint256 agentId, string calldata newURI) external;

    /// @notice Get the token URI for a given agent ID.
    function tokenURI(uint256 tokenId) external view returns (string memory);

    // ─── Wallet Management ───────────────────────────────────────────────

    /// @notice Link a wallet address to an agent. Requires EIP-712 signature from the new wallet
    ///         (for EOAs) or ERC-1271 validation (for contract wallets).
    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Get the wallet address linked to an agent.
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Remove the linked wallet from an agent.
    function unsetAgentWallet(uint256 agentId) external;

    // ─── Metadata ────────────────────────────────────────────────────────

    /// @notice Set a metadata entry for an agent.
    function setMetadata(uint256 agentId, string calldata metadataKey, bytes calldata metadataValue) external;

    /// @notice Read a metadata entry for an agent.
    function getMetadata(uint256 agentId, string calldata metadataKey) external view returns (bytes memory);

    // ─── ERC-721 Standard ────────────────────────────────────────────────

    function ownerOf(uint256 tokenId) external view returns (address);

    function transferFrom(address from, address to, uint256 tokenId) external;

    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function approve(address to, uint256 tokenId) external;

    function setApprovalForAll(address operator, bool approved) external;

    function getApproved(uint256 tokenId) external view returns (address);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function balanceOf(address owner) external view returns (uint256);
}
