// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AgentFactory} from "../src/AgentFactory.sol";

contract DeployFactoryV3 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        AgentFactory factory = new AgentFactory(
            0x8004A169FB4a3325136EB29fA0ceB6D2e539a432, // IdentityRegistry
            0x8004BAa17C55a88189AE136b182e5fdA19dE9b63, // ReputationRegistry
            0x6F6B8F1a20703309951a5127c45B49b1CD981A22, // BondingCurveRouter
            0x7e78A8DE94f21804F7a17F4E8BF9EC2c872187ea, // Lens
            deployer
        );

        console2.log("AgentFactory v3:", address(factory));

        vm.stopBroadcast();
    }
}
