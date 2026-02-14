// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {RevenueRouter} from "../src/RevenueRouter.sol";
import {AgentRating} from "../src/AgentRating.sol";

/// @title Deploy
/// @notice Deployment script for ClawNad smart contracts on Monad.
/// @dev Usage:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url https://rpc.monad.xyz \
///     --broadcast \
///     --verify \
///     --etherscan-api-key $MONADSCAN_API_KEY \
///     -vvvv
contract Deploy is Script {
    // ─── Monad Mainnet External Contracts ─────────────────────────────────
    // ERC-8004 (verify these are deployed on Monad; deploy your own if not)
    address constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant REPUTATION_REGISTRY = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;

    // nad.fun
    address constant BONDING_CURVE_ROUTER = 0x6F6B8F1a20703309951a5127c45B49b1CD981A22;
    address constant LENS = 0x7e78A8DE94f21804F7a17F4E8BF9EC2c872187ea;

    // Revenue config
    uint256 constant PLATFORM_FEE_BPS = 200; // 2%
    uint256 constant BUYBACK_BPS = 3_000; // 30%

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AgentFactory
        AgentFactory factory = new AgentFactory(
            IDENTITY_REGISTRY,
            REPUTATION_REGISTRY,
            BONDING_CURVE_ROUTER,
            LENS,
            deployer // deployer is owner, can transfer later via Ownable2Step
        );
        console2.log("AgentFactory deployed at:", address(factory));

        // 2. Deploy RevenueRouter (no supported tokens yet — add via addSupportedToken later)
        address[] memory supportedTokens = new address[](0);

        RevenueRouter revenueRouter = new RevenueRouter(
            address(factory),
            deployer, // deployer is treasury, can update via setTreasury later
            PLATFORM_FEE_BPS,
            BUYBACK_BPS,
            supportedTokens,
            deployer
        );
        console2.log("RevenueRouter deployed at:", address(revenueRouter));

        // 3. Deploy AgentRating
        AgentRating agentRating = new AgentRating(REPUTATION_REGISTRY, address(factory));
        console2.log("AgentRating deployed at:", address(agentRating));

        vm.stopBroadcast();

        // Log summary
        console2.log("\n=== ClawNad Deployment Summary ===");
        console2.log("Chain ID:        143 (Monad)");
        console2.log("AgentFactory:   ", address(factory));
        console2.log("RevenueRouter:  ", address(revenueRouter));
        console2.log("AgentRating:    ", address(agentRating));
        console2.log("Owner/Treasury: ", deployer);
        console2.log("Platform Fee:    2%");
        console2.log("Buyback:         30%");
    }
}

/// @title DeployTestnet
/// @notice Simplified deployment for Monad testnet with deployer as owner/treasury.
contract DeployTestnet is Script {
    // ERC-8004 on testnet (may need to deploy your own)
    address constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant REPUTATION_REGISTRY = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;

    // nad.fun on testnet (verify addresses)
    address constant BONDING_CURVE_ROUTER = 0x6F6B8F1a20703309951a5127c45B49b1CD981A22;
    address constant LENS = 0x7e78A8DE94f21804F7a17F4E8BF9EC2c872187ea;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        AgentFactory factory = new AgentFactory(
            IDENTITY_REGISTRY,
            REPUTATION_REGISTRY,
            BONDING_CURVE_ROUTER,
            LENS,
            deployer
        );
        console2.log("AgentFactory:", address(factory));

        // No USDC on testnet — deploy with empty token list, add later
        address[] memory tokens = new address[](0);
        RevenueRouter revenueRouter = new RevenueRouter(
            address(factory),
            deployer, // deployer is treasury on testnet
            200, // 2%
            3_000, // 30%
            tokens,
            deployer
        );
        console2.log("RevenueRouter:", address(revenueRouter));

        AgentRating agentRating = new AgentRating(REPUTATION_REGISTRY, address(factory));
        console2.log("AgentRating:", address(agentRating));

        vm.stopBroadcast();
    }
}
