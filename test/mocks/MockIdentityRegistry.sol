// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IIdentityRegistry, MetadataEntry} from "../../src/interfaces/IIdentityRegistry.sol";

/// @notice Minimal mock of the ERC-8004 Identity Registry for testing.
contract MockIdentityRegistry is ERC721 {
    uint256 private _nextTokenId = 1;

    mapping(uint256 => string) private _agentURIs;
    mapping(uint256 => address) private _agentWallets;
    mapping(uint256 => mapping(string => bytes)) private _metadata;

    constructor() ERC721("ERC8004 Identity", "AGENT") {}

    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId) {
        agentId = _nextTokenId++;
        _safeMint(msg.sender, agentId);
        _agentURIs[agentId] = agentURI;

        for (uint256 i; i < metadata.length; ++i) {
            _metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
        }
    }

    function register(string calldata agentURI) external returns (uint256 agentId) {
        agentId = _nextTokenId++;
        _safeMint(msg.sender, agentId);
        _agentURIs[agentId] = agentURI;
    }

    function register() external returns (uint256 agentId) {
        agentId = _nextTokenId++;
        _safeMint(msg.sender, agentId);
    }

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(ownerOf(agentId) == msg.sender || getApproved(agentId) == msg.sender, "Not authorized");
        _agentURIs[agentId] = newURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _agentURIs[tokenId];
    }

    function setAgentWallet(uint256 agentId, address newWallet, uint256, bytes calldata) external {
        require(ownerOf(agentId) == msg.sender, "Not owner");
        _agentWallets[agentId] = newWallet;
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _agentWallets[agentId];
    }

    function unsetAgentWallet(uint256 agentId) external {
        require(ownerOf(agentId) == msg.sender, "Not owner");
        delete _agentWallets[agentId];
    }

    function setMetadata(uint256 agentId, string calldata metadataKey, bytes calldata metadataValue) external {
        require(ownerOf(agentId) == msg.sender || getApproved(agentId) == msg.sender, "Not authorized");
        _metadata[agentId][metadataKey] = metadataValue;
    }

    function getMetadata(uint256 agentId, string calldata metadataKey) external view returns (bytes memory) {
        return _metadata[agentId][metadataKey];
    }
}
