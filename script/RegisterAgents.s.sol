// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentRating} from "../src/AgentRating.sol";
import {IBondingCurveRouter, TokenCreationParams, ILens} from "../src/interfaces/INadFun.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";

/// @title RegisterAgents
/// @notice End-to-end mainnet test: register agents + create tokens + link them.
/// @dev Usage:
///   export $(grep -v '^#' ../.env | xargs)
///   forge script script/RegisterAgents.s.sol:RegisterAgents \
///     --rpc-url https://rpc.monad.xyz \
///     --broadcast -vvvv
contract RegisterAgents is Script {
    // ─── Deployed ClawNad Contracts ─────────────────────────────────────
    AgentFactory constant FACTORY = AgentFactory(payable(0xB541a987B9B217e6336F9080bbEC5630Bf3E8Dde));
    AgentRating constant RATING = AgentRating(0xB167BBa391b7C1C5D3e3b7Ae8034e43E5bb44306);

    // ─── nad.fun ────────────────────────────────────────────────────────
    IBondingCurveRouter constant ROUTER = IBondingCurveRouter(0x6F6B8F1a20703309951a5127c45B49b1CD981A22);
    ILens constant LENS = ILens(0x7e78A8DE94f21804F7a17F4E8BF9EC2c872187ea);

    uint256 constant DEPLOY_FEE = 10 ether; // 10 MON

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console2.log("=== ClawNad E2E Test ===");
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);
        console2.log("");

        vm.startBroadcast(pk);

        // ─────────────────────────────────────────────────────────────────
        // Step 1: Register 3 agents via AgentFactory (ERC-8004 identity only)
        // ─────────────────────────────────────────────────────────────────
        console2.log("--- Step 1: Register Agents (ERC-8004 identity) ---");

        uint256 agent1Id = FACTORY.registerAgent(
            "https://clawnad.dev/agents/summarybot.json",
            "https://api.clawnad.dev/agents/summarybot"
        );
        console2.log("Agent 1 (SummaryBot) ID:", agent1Id);

        uint256 agent2Id = FACTORY.registerAgent(
            "https://clawnad.dev/agents/codeauditor.json",
            "https://api.clawnad.dev/agents/codeauditor"
        );
        console2.log("Agent 2 (CodeAuditor) ID:", agent2Id);

        uint256 agent3Id = FACTORY.registerAgent(
            "https://clawnad.dev/agents/orchestrator.json",
            "https://api.clawnad.dev/agents/orchestrator"
        );
        console2.log("Agent 3 (Orchestrator) ID:", agent3Id);

        // ─────────────────────────────────────────────────────────────────
        // Step 2: Create tokens directly on nad.fun (from EOA)
        // ─────────────────────────────────────────────────────────────────
        console2.log("");
        console2.log("--- Step 2: Create nad.fun Tokens ---");

        (address token1,) = ROUTER.create{value: DEPLOY_FEE}(
            TokenCreationParams({
                name: "SummaryBot",
                symbol: "SUMM",
                tokenURI: "https://clawnad.dev/tokens/summarybot.json",
                amountOut: 0,
                salt: keccak256(abi.encodePacked(deployer, agent1Id, block.number)),
                actionId: 1
            })
        );
        console2.log("Token 1 (SUMM):", token1);

        (address token2,) = ROUTER.create{value: DEPLOY_FEE}(
            TokenCreationParams({
                name: "CodeAuditor",
                symbol: "AUDIT",
                tokenURI: "https://clawnad.dev/tokens/codeauditor.json",
                amountOut: 0,
                salt: keccak256(abi.encodePacked(deployer, agent2Id, block.number)),
                actionId: 1
            })
        );
        console2.log("Token 2 (AUDIT):", token2);

        (address token3,) = ROUTER.create{value: DEPLOY_FEE}(
            TokenCreationParams({
                name: "Orchestrator",
                symbol: "ORCH",
                tokenURI: "https://clawnad.dev/tokens/orchestrator.json",
                amountOut: 0,
                salt: keccak256(abi.encodePacked(deployer, agent3Id, block.number)),
                actionId: 1
            })
        );
        console2.log("Token 3 (ORCH):", token3);

        // ─────────────────────────────────────────────────────────────────
        // Step 3: Link tokens to agents
        // ─────────────────────────────────────────────────────────────────
        console2.log("");
        console2.log("--- Step 3: Link Tokens to Agents ---");

        FACTORY.linkToken(agent1Id, token1);
        console2.log("Agent 1 linked to SUMM");

        FACTORY.linkToken(agent2Id, token2);
        console2.log("Agent 2 linked to AUDIT");

        FACTORY.linkToken(agent3Id, token3);
        console2.log("Agent 3 linked to ORCH");

        vm.stopBroadcast();

        // ─────────────────────────────────────────────────────────────────
        // Step 4: Verify everything (read-only)
        // ─────────────────────────────────────────────────────────────────
        console2.log("");
        console2.log("=== Verification ===");

        // Verify agents
        AgentFactory.AgentInfo memory info1 = FACTORY.getAgent(agent1Id);
        console2.log("Agent 1 - active:", info1.active, "token:", info1.token);

        AgentFactory.AgentInfo memory info2 = FACTORY.getAgent(agent2Id);
        console2.log("Agent 2 - active:", info2.active, "token:", info2.token);

        AgentFactory.AgentInfo memory info3 = FACTORY.getAgent(agent3Id);
        console2.log("Agent 3 - active:", info3.active, "token:", info3.token);

        // Factory state
        console2.log("Total agents:", FACTORY.totalAgents());

        // Reverse lookups
        console2.log("Token1 -> AgentId:", FACTORY.tokenToAgent(token1));
        console2.log("Token2 -> AgentId:", FACTORY.tokenToAgent(token2));

        // nad.fun Lens queries
        console2.log("Agent 1 progress:", LENS.getProgress(token1));
        console2.log("Agent 1 graduated:", LENS.isGraduated(token1));

        // Creator tracking
        uint256[] memory myAgents = FACTORY.getAgentsByCreator(deployer);
        console2.log("My total agents:", myAgents.length);

        // NFT ownership
        IIdentityRegistry registry = FACTORY.identityRegistry();
        console2.log("Agent 1 NFT owner:", registry.ownerOf(agent1Id));
        console2.log("Agent 2 NFT owner:", registry.ownerOf(agent2Id));
        console2.log("Agent 3 NFT owner:", registry.ownerOf(agent3Id));

        console2.log("");
        console2.log("=== E2E Test Complete ===");
        console2.log("3 agents registered, 3 tokens created, all linked!");
        console2.log("Cost: 30 MON (3 x 10 MON deploy fee) + gas");
    }
}
