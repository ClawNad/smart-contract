// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";

/// @title FixupAgents
/// @notice Complete the E2E setup: register missing agents + link all tokens.
contract FixupAgents is Script {
    AgentFactory constant FACTORY = AgentFactory(payable(0xB541a987B9B217e6336F9080bbEC5630Bf3E8Dde));

    // Tokens already created on nad.fun
    address constant SUMM_TOKEN = 0xf365D566ed38FA3284826A593198c9864E098E0c;
    address constant AUDIT_TOKEN = 0xC4ea1E7248396032796F6464563f50bC1cF8572D;
    address constant ORCH_TOKEN = 0x254B90766dc64099bED6482A3d99F6e3b740e6Aa;

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console2.log("=== ClawNad Fixup Script ===");
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance);

        vm.startBroadcast(pk);

        // Agent 124 already registered — register 125 and 126
        console2.log("");
        console2.log("--- Register missing agents ---");

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

        // Link all 3 tokens
        console2.log("");
        console2.log("--- Link tokens to agents ---");

        FACTORY.linkToken(124, SUMM_TOKEN);
        console2.log("Agent 124 linked to SUMM");

        FACTORY.linkToken(agent2Id, AUDIT_TOKEN);
        console2.log("Agent 2 linked to AUDIT");

        FACTORY.linkToken(agent3Id, ORCH_TOKEN);
        console2.log("Agent 3 linked to ORCH");

        vm.stopBroadcast();

        // Verify
        console2.log("");
        console2.log("=== Verification ===");

        AgentFactory.AgentInfo memory info1 = FACTORY.getAgent(124);
        console2.log("Agent 124 - active:", info1.active, "token:", info1.token);

        AgentFactory.AgentInfo memory info2 = FACTORY.getAgent(agent2Id);
        console2.log("Agent 2 - active:", info2.active, "token:", info2.token);

        AgentFactory.AgentInfo memory info3 = FACTORY.getAgent(agent3Id);
        console2.log("Agent 3 - active:", info3.active, "token:", info3.token);

        console2.log("Total agents:", FACTORY.totalAgents());

        IIdentityRegistry registry = FACTORY.identityRegistry();
        console2.log("Agent 124 NFT owner:", registry.ownerOf(124));
        console2.log("Agent 2 NFT owner:", registry.ownerOf(agent2Id));
        console2.log("Agent 3 NFT owner:", registry.ownerOf(agent3Id));

        console2.log("");
        console2.log("=== Fixup Complete ===");
    }
}
