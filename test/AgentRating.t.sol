// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentRating} from "../src/AgentRating.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";
import {MockReputationRegistry} from "./mocks/MockReputationRegistry.sol";
import {MockBondingCurveRouter} from "./mocks/MockBondingCurveRouter.sol";
import {MockLens} from "./mocks/MockLens.sol";

contract AgentRatingTest is Test {
    AgentFactory public factory;
    AgentRating public rating;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockBondingCurveRouter public bondingCurveRouter;
    MockLens public lens;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice"); // agent creator
    address public bob = makeAddr("bob"); // rater

    uint256 public constant DEPLOY_FEE = 10 ether;
    uint256 public agentId;

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

        rating = new AgentRating(address(reputationRegistry), address(factory));

        // Launch an agent
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        (agentId,) = factory.launchAgent{value: DEPLOY_FEE}(
            AgentFactory.LaunchParams({
                agentURI: "ipfs://test",
                endpoint: "https://agent.dev",
                tokenName: "TestAgent",
                tokenSymbol: "TAGT",
                tokenURI: "ipfs://token",
                initialBuyAmount: 0,
                salt: keccak256("test-salt")
            })
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      RATE AGENT
    // ═══════════════════════════════════════════════════════════════════════

    function test_rateAgent_success() public {
        vm.prank(bob);
        rating.rateAgent(agentId, 500, "accuracy", "", "", bytes32(0));

        // Verify feedback was submitted to reputation registry
        assertEq(reputationRegistry.feedbackCount(agentId), 1);
        assertEq(reputationRegistry.feedbackSum(agentId), 500);
    }

    function test_rateAgent_emitsEvent() public {
        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit AgentRating.AgentRated(agentId, bob, 450, "speed", "", bytes32(0));
        rating.rateAgent(agentId, 450, "speed", "", "", bytes32(0));
    }

    function test_rateAgent_withFeedbackURI() public {
        bytes32 hash = keccak256("detailed feedback");

        vm.prank(bob);
        rating.rateAgent(agentId, 300, "reliability", "issues", "ipfs://QmFeedback", hash);

        // Feedback is stored under the AgentRating contract address (it's the msg.sender
        // when calling the reputation registry), not the original caller.
        (int128 value, uint8 decimals, string memory tag1, string memory tag2, bool isRevoked) =
            reputationRegistry.readFeedback(agentId, address(rating), 0);

        assertEq(value, 300);
        assertEq(decimals, 2);
        assertEq(tag1, "reliability");
        assertEq(tag2, "issues");
        assertFalse(isRevoked);
    }

    function test_rateAgent_multipleRatings() public {
        address carol = makeAddr("carol");

        vm.prank(bob);
        rating.rateAgent(agentId, 500, "accuracy", "", "", bytes32(0));

        vm.prank(carol);
        rating.rateAgent(agentId, 400, "speed", "", "", bytes32(0));

        assertEq(reputationRegistry.feedbackCount(agentId), 2);
        assertEq(reputationRegistry.feedbackSum(agentId), 900); // 500 + 400
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    function test_rateAgent_revertsOnScoreTooLow() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AgentRating.AgentRating__ScoreOutOfRange.selector, int128(99)));
        rating.rateAgent(agentId, 99, "accuracy", "", "", bytes32(0));
    }

    function test_rateAgent_revertsOnScoreTooHigh() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AgentRating.AgentRating__ScoreOutOfRange.selector, int128(501)));
        rating.rateAgent(agentId, 501, "accuracy", "", "", bytes32(0));
    }

    function test_rateAgent_revertsOnEmptyTag() public {
        vm.prank(bob);
        vm.expectRevert(AgentRating.AgentRating__EmptyTag.selector);
        rating.rateAgent(agentId, 500, "", "", "", bytes32(0));
    }

    function test_rateAgent_revertsIfAgentInactive() public {
        vm.prank(alice);
        factory.deactivateAgent(agentId);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AgentRating.AgentRating__AgentNotActive.selector, agentId));
        rating.rateAgent(agentId, 500, "accuracy", "", "", bytes32(0));
    }

    function test_rateAgent_boundaryCases() public {
        // Minimum score
        vm.prank(bob);
        rating.rateAgent(agentId, 100, "min", "", "", bytes32(0));

        // Maximum score
        address carol = makeAddr("carol");
        vm.prank(carol);
        rating.rateAgent(agentId, 500, "max", "", "", bytes32(0));

        assertEq(reputationRegistry.feedbackCount(agentId), 2);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_constants() public view {
        assertEq(rating.VALUE_DECIMALS(), 2);
        assertEq(rating.MIN_SCORE(), 100);
        assertEq(rating.MAX_SCORE(), 500);
    }

    function test_immutables() public view {
        assertEq(address(rating.reputationRegistry()), address(reputationRegistry));
        assertEq(address(rating.factory()), address(factory));
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(AgentRating.AgentRating__ZeroAddress.selector);
        new AgentRating(address(0), address(factory));

        vm.expectRevert(AgentRating.AgentRating__ZeroAddress.selector);
        new AgentRating(address(reputationRegistry), address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      FUZZ
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_rateAgent_validScoreRange(int128 score) public {
        score = int128(bound(int256(score), 100, 500));

        vm.prank(bob);
        rating.rateAgent(agentId, score, "fuzz", "", "", bytes32(0));

        assertEq(reputationRegistry.feedbackCount(agentId), 1);
    }
}
