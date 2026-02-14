// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {AgentFactory} from "../src/AgentFactory.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";
import {MockReputationRegistry} from "./mocks/MockReputationRegistry.sol";
import {MockBondingCurveRouter} from "./mocks/MockBondingCurveRouter.sol";
import {MockLens} from "./mocks/MockLens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AgentFactoryTest is Test {
    AgentFactory public factory;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockBondingCurveRouter public bondingCurveRouter;
    MockLens public lens;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant DEPLOY_FEE = 10 ether;

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        bondingCurveRouter = new MockBondingCurveRouter();
        lens = new MockLens();

        factory = new AgentFactory(
            address(identityRegistry),
            address(reputationRegistry),
            address(bondingCurveRouter),
            address(lens),
            owner
        );

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    function test_constructor_setsImmutables() public view {
        assertEq(address(factory.identityRegistry()), address(identityRegistry));
        assertEq(address(factory.reputationRegistry()), address(reputationRegistry));
        assertEq(address(factory.bondingCurveRouter()), address(bondingCurveRouter));
        assertEq(address(factory.lens()), address(lens));
        assertEq(factory.owner(), owner);
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(AgentFactory.AgentFactory__ZeroAddress.selector);
        new AgentFactory(address(0), address(reputationRegistry), address(bondingCurveRouter), address(lens), owner);

        vm.expectRevert(AgentFactory.AgentFactory__ZeroAddress.selector);
        new AgentFactory(address(identityRegistry), address(0), address(bondingCurveRouter), address(lens), owner);

        vm.expectRevert(AgentFactory.AgentFactory__ZeroAddress.selector);
        new AgentFactory(address(identityRegistry), address(reputationRegistry), address(0), address(lens), owner);

        vm.expectRevert(AgentFactory.AgentFactory__ZeroAddress.selector);
        new AgentFactory(address(identityRegistry), address(reputationRegistry), address(bondingCurveRouter), address(0), owner);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      LAUNCH AGENT
    // ═══════════════════════════════════════════════════════════════════════

    function test_launchAgent_success() public {
        AgentFactory.LaunchParams memory params = _defaultLaunchParams();

        vm.prank(alice);
        (uint256 agentId, address token) = factory.launchAgent{value: DEPLOY_FEE}(params);

        // Agent stored correctly
        AgentFactory.AgentInfo memory agent = factory.getAgent(agentId);
        assertEq(agent.agentId, agentId);
        assertEq(agent.token, token);
        assertEq(agent.creator, alice);
        assertEq(agent.agentWallet, alice);
        assertEq(agent.endpoint, "https://summary.clawnad.dev");
        assertTrue(agent.active);
        assertEq(agent.launchedAt, block.timestamp);

        // ERC-8004 NFT transferred to alice
        assertEq(identityRegistry.ownerOf(agentId), alice);

        // Reverse lookups
        assertEq(factory.tokenToAgent(token), agentId);
        assertTrue(factory.isAgentToken(token));
        assertEq(factory.totalAgents(), 1);

        // Creator tracking
        uint256[] memory aliceAgents = factory.getAgentsByCreator(alice);
        assertEq(aliceAgents.length, 1);
        assertEq(aliceAgents[0], agentId);
    }

    function test_launchAgent_emitsEvent() public {
        AgentFactory.LaunchParams memory params = _defaultLaunchParams();

        vm.prank(alice);
        vm.expectEmit(false, false, true, false);
        emit AgentFactory.AgentLaunched(0, address(0), alice, "", "", "", "");
        factory.launchAgent{value: DEPLOY_FEE}(params);
    }

    function test_launchAgent_refundsExcessMON() public {
        AgentFactory.LaunchParams memory params = _defaultLaunchParams();

        uint256 balBefore = alice.balance;

        vm.prank(alice);
        factory.launchAgent{value: 15 ether}(params);

        // Alice should get 5 ether refunded (sent 15, deploy costs 10)
        assertEq(alice.balance, balBefore - DEPLOY_FEE);
    }

    function test_launchAgent_revertsOnEmptyURI() public {
        AgentFactory.LaunchParams memory params = _defaultLaunchParams();
        params.agentURI = "";

        vm.prank(alice);
        vm.expectRevert(AgentFactory.AgentFactory__EmptyURI.selector);
        factory.launchAgent{value: DEPLOY_FEE}(params);
    }

    function test_launchAgent_revertsOnEmptyName() public {
        AgentFactory.LaunchParams memory params = _defaultLaunchParams();
        params.tokenName = "";

        vm.prank(alice);
        vm.expectRevert(AgentFactory.AgentFactory__EmptyName.selector);
        factory.launchAgent{value: DEPLOY_FEE}(params);
    }

    function test_launchAgent_revertsOnEmptySymbol() public {
        AgentFactory.LaunchParams memory params = _defaultLaunchParams();
        params.tokenSymbol = "";

        vm.prank(alice);
        vm.expectRevert(AgentFactory.AgentFactory__EmptySymbol.selector);
        factory.launchAgent{value: DEPLOY_FEE}(params);
    }

    function test_launchAgent_revertsWhenPaused() public {
        vm.prank(owner);
        factory.pause();

        AgentFactory.LaunchParams memory params = _defaultLaunchParams();

        vm.prank(alice);
        vm.expectRevert();
        factory.launchAgent{value: DEPLOY_FEE}(params);
    }

    function test_launchAgent_multipleAgents() public {
        AgentFactory.LaunchParams memory params1 = _defaultLaunchParams();
        params1.tokenName = "Agent1";
        params1.tokenSymbol = "A1";

        AgentFactory.LaunchParams memory params2 = _defaultLaunchParams();
        params2.tokenName = "Agent2";
        params2.tokenSymbol = "A2";

        vm.startPrank(alice);
        (uint256 id1,) = factory.launchAgent{value: DEPLOY_FEE}(params1);
        (uint256 id2,) = factory.launchAgent{value: DEPLOY_FEE}(params2);
        vm.stopPrank();

        assertEq(factory.totalAgents(), 2);
        assertTrue(id1 != id2);

        uint256[] memory aliceAgents = factory.getAgentsByCreator(alice);
        assertEq(aliceAgents.length, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      REGISTER AGENT (no token)
    // ═══════════════════════════════════════════════════════════════════════

    function test_registerAgent_success() public {
        vm.prank(alice);
        uint256 agentId = factory.registerAgent("ipfs://Qm.../agent.json", "https://my-agent.dev");

        AgentFactory.AgentInfo memory agent = factory.getAgent(agentId);
        assertEq(agent.token, address(0));
        assertEq(agent.creator, alice);
        assertTrue(agent.active);

        // NFT transferred to alice
        assertEq(identityRegistry.ownerOf(agentId), alice);
    }

    function test_registerAgent_revertsOnEmptyURI() public {
        vm.prank(alice);
        vm.expectRevert(AgentFactory.AgentFactory__EmptyURI.selector);
        factory.registerAgent("", "https://my-agent.dev");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      LINK TOKEN
    // ═══════════════════════════════════════════════════════════════════════

    function test_linkToken_success() public {
        // Register agent without token
        vm.prank(alice);
        uint256 agentId = factory.registerAgent("ipfs://Qm.../agent.json", "https://my-agent.dev");

        // Link a token
        address fakeToken = makeAddr("fakeToken");
        vm.prank(alice);
        factory.linkToken(agentId, fakeToken);

        AgentFactory.AgentInfo memory agent = factory.getAgent(agentId);
        assertEq(agent.token, fakeToken);
        assertEq(factory.tokenToAgent(fakeToken), agentId);
    }

    function test_linkToken_revertsIfNotOwner() public {
        vm.prank(alice);
        uint256 agentId = factory.registerAgent("ipfs://Qm.../agent.json", "https://my-agent.dev");

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__NotAgentOwner.selector, agentId, bob));
        factory.linkToken(agentId, makeAddr("token"));
    }

    function test_linkToken_revertsIfAlreadyLinked() public {
        // Launch with token
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__TokenAlreadyLinked.selector, agentId));
        factory.linkToken(agentId, makeAddr("token2"));
    }

    function test_linkToken_revertsIfTokenAlreadyUsed() public {
        // Register two agents
        vm.startPrank(alice);
        uint256 id1 = factory.registerAgent("ipfs://a1", "https://a1.dev");
        uint256 id2 = factory.registerAgent("ipfs://a2", "https://a2.dev");

        address token = makeAddr("sharedToken");
        factory.linkToken(id1, token);

        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__TokenAlreadyUsed.selector, token));
        factory.linkToken(id2, token);
        vm.stopPrank();
    }

    function test_linkToken_revertsOnZeroAddress() public {
        vm.prank(alice);
        uint256 agentId = factory.registerAgent("ipfs://Qm.../agent.json", "https://my-agent.dev");

        vm.prank(alice);
        vm.expectRevert(AgentFactory.AgentFactory__ZeroAddress.selector);
        factory.linkToken(agentId, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      UPDATE ENDPOINT
    // ═══════════════════════════════════════════════════════════════════════

    function test_updateEndpoint_success() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(alice);
        factory.updateEndpoint(agentId, "https://new-endpoint.dev");

        assertEq(factory.getAgent(agentId).endpoint, "https://new-endpoint.dev");
    }

    function test_updateEndpoint_revertsIfNotOwner() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__NotAgentOwner.selector, agentId, bob));
        factory.updateEndpoint(agentId, "https://hacked.dev");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      UPDATE AGENT WALLET
    // ═══════════════════════════════════════════════════════════════════════

    function test_updateAgentWallet_success() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        address newWallet = makeAddr("newWallet");
        vm.prank(alice);
        factory.updateAgentWallet(agentId, newWallet);

        assertEq(factory.getAgent(agentId).agentWallet, newWallet);
    }

    function test_updateAgentWallet_revertsOnZero() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(alice);
        vm.expectRevert(AgentFactory.AgentFactory__ZeroAddress.selector);
        factory.updateAgentWallet(agentId, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      DEACTIVATE / REACTIVATE
    // ═══════════════════════════════════════════════════════════════════════

    function test_deactivateAgent_success() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(alice);
        factory.deactivateAgent(agentId);

        assertFalse(factory.getAgent(agentId).active);
    }

    function test_deactivateAgent_revertsIfAlreadyInactive() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(alice);
        factory.deactivateAgent(agentId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__AgentNotActive.selector, agentId));
        factory.deactivateAgent(agentId);
    }

    function test_reactivateAgent_success() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(alice);
        factory.deactivateAgent(agentId);
        assertFalse(factory.getAgent(agentId).active);

        vm.prank(alice);
        factory.reactivateAgent(agentId);
        assertTrue(factory.getAgent(agentId).active);
    }

    function test_reactivateAgent_revertsIfAlreadyActive() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__AgentAlreadyActive.selector, agentId));
        factory.reactivateAgent(agentId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      READ FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function test_getAgentByToken_success() public {
        vm.prank(alice);
        (uint256 agentId, address token) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        AgentFactory.AgentInfo memory agent = factory.getAgentByToken(token);
        assertEq(agent.agentId, agentId);
    }

    function test_getAgentByToken_revertsIfNotFound() public {
        address randomToken = makeAddr("random");
        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__TokenNotFound.selector, randomToken));
        factory.getAgentByToken(randomToken);
    }

    function test_getAgent_revertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__AgentNotFound.selector, 999));
        factory.getAgent(999);
    }

    function test_agentExists() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        assertTrue(factory.agentExists(agentId));
        assertFalse(factory.agentExists(999));
    }

    function test_getTokenProgress() public {
        vm.prank(alice);
        (uint256 agentId, address token) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        lens.setProgress(token, 5000);
        assertEq(factory.getTokenProgress(agentId), 5000);
    }

    function test_isTokenGraduated() public {
        vm.prank(alice);
        (uint256 agentId, address token) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        assertFalse(factory.isTokenGraduated(agentId));

        lens.setGraduated(token, true);
        assertTrue(factory.isTokenGraduated(agentId));
    }

    function test_getTokenProgress_revertsIfNoToken() public {
        vm.prank(alice);
        uint256 agentId = factory.registerAgent("ipfs://test", "https://test.dev");

        vm.expectRevert(abi.encodeWithSelector(AgentFactory.AgentFactory__NoTokenLinked.selector, agentId));
        factory.getTokenProgress(agentId);
    }

    function test_getAgentReputation() public {
        vm.prank(alice);
        (uint256 agentId,) = factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        // Submit some feedback directly to the mock reputation registry
        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 500, 2, "accuracy", "", "", "", bytes32(0));

        (uint64 count, int256 value, uint8 decimals) = factory.getAgentReputation(agentId);
        assertEq(count, 1);
        assertEq(value, 500);
        assertEq(decimals, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function test_pause_unpause() public {
        vm.prank(owner);
        factory.pause();

        vm.prank(alice);
        vm.expectRevert();
        factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());

        vm.prank(owner);
        factory.unpause();

        vm.prank(alice);
        factory.launchAgent{value: DEPLOY_FEE}(_defaultLaunchParams());
    }

    function test_pause_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.pause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _defaultLaunchParams() internal pure returns (AgentFactory.LaunchParams memory) {
        return AgentFactory.LaunchParams({
            agentURI: "ipfs://QmTest/agent-registration.json",
            endpoint: "https://summary.clawnad.dev",
            tokenName: "SummaryBot",
            tokenSymbol: "SUMM",
            tokenURI: "ipfs://QmTest/token-metadata.json",
            initialBuyAmount: 0,
            salt: keccak256("test-salt")
        });
    }
}
