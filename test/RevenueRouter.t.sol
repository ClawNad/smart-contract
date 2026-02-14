// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {AgentFactory} from "../src/AgentFactory.sol";
import {RevenueRouter} from "../src/RevenueRouter.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";
import {MockReputationRegistry} from "./mocks/MockReputationRegistry.sol";
import {MockBondingCurveRouter} from "./mocks/MockBondingCurveRouter.sol";
import {MockLens} from "./mocks/MockLens.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RevenueRouterTest is Test {
    AgentFactory public factory;
    RevenueRouter public router;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockBondingCurveRouter public bondingCurveRouter;
    MockLens public lens;
    MockUSDC public usdc;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice"); // agent creator
    address public bob = makeAddr("bob"); // revenue depositor

    uint256 public constant DEPLOY_FEE = 10 ether;
    uint256 public constant PLATFORM_FEE_BPS = 200; // 2%
    uint256 public constant BUYBACK_BPS = 3_000; // 30%

    uint256 public agentId;

    function setUp() public {
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        bondingCurveRouter = new MockBondingCurveRouter();
        lens = new MockLens();
        usdc = new MockUSDC();

        factory = new AgentFactory(
            address(identityRegistry),
            address(reputationRegistry),
            address(bondingCurveRouter),
            address(lens),
            owner
        );

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        router = new RevenueRouter(
            address(factory), treasury, PLATFORM_FEE_BPS, BUYBACK_BPS, tokens, owner
        );

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

        // Give bob some USDC
        usdc.mint(bob, 1_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    function test_constructor_setsConfig() public view {
        assertEq(address(router.factory()), address(factory));
        assertEq(router.treasury(), treasury);
        assertEq(router.platformFeeBps(), PLATFORM_FEE_BPS);
        assertEq(router.buybackBps(), BUYBACK_BPS);
        assertTrue(router.supportedTokens(address(usdc)));
    }

    function test_constructor_revertsOnHighFee() public {
        address[] memory tokens = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(RevenueRouter.RevenueRouter__FeeTooHigh.selector, 1_001));
        new RevenueRouter(address(factory), treasury, 1_001, BUYBACK_BPS, tokens, owner);

        vm.expectRevert(abi.encodeWithSelector(RevenueRouter.RevenueRouter__FeeTooHigh.selector, 5_001));
        new RevenueRouter(address(factory), treasury, PLATFORM_FEE_BPS, 5_001, tokens, owner);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      DEPOSIT
    // ═══════════════════════════════════════════════════════════════════════

    function test_deposit_success() public {
        uint256 amount = 1_000 ether;

        vm.startPrank(bob);
        usdc.approve(address(router), amount);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();

        RevenueRouter.RevenueRecord memory record = router.getRevenue(agentId, address(usdc));
        assertEq(record.totalDeposited, amount);
        assertEq(record.totalDistributed, 0);
        assertEq(usdc.balanceOf(address(router)), amount);
    }

    function test_deposit_emitsEvent() public {
        uint256 amount = 500 ether;

        vm.startPrank(bob);
        usdc.approve(address(router), amount);

        vm.expectEmit(true, true, true, true);
        emit RevenueRouter.RevenueDeposited(agentId, address(usdc), amount, bob);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();
    }

    function test_deposit_revertsOnUnsupportedToken() public {
        address fakeToken = makeAddr("fakeToken");

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(RevenueRouter.RevenueRouter__UnsupportedToken.selector, fakeToken));
        router.depositRevenue(agentId, fakeToken, 100 ether);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(bob);
        vm.expectRevert(RevenueRouter.RevenueRouter__ZeroAmount.selector);
        router.depositRevenue(agentId, address(usdc), 0);
    }

    function test_deposit_revertsIfAgentInactive() public {
        vm.prank(alice);
        factory.deactivateAgent(agentId);

        vm.startPrank(bob);
        usdc.approve(address(router), 100 ether);
        vm.expectRevert(abi.encodeWithSelector(RevenueRouter.RevenueRouter__AgentNotActive.selector, agentId));
        router.depositRevenue(agentId, address(usdc), 100 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      DISTRIBUTE
    // ═══════════════════════════════════════════════════════════════════════

    function test_distribute_correctSplits() public {
        uint256 amount = 10_000 ether;

        // Deposit
        vm.startPrank(bob);
        usdc.approve(address(router), amount);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();

        // Distribute
        router.distribute(agentId, address(usdc));

        // Expected splits:
        // platformFee = 10000 * 200 / 10000 = 200 (2%)
        // remaining   = 10000 - 200 = 9800
        // buyback     = 9800 * 3000 / 10000 = 2940 (30% of remaining)
        // agentShare  = 9800 - 2940 = 6860

        uint256 expectedPlatformFee = 200 ether;
        uint256 expectedBuyback = 2_940 ether;
        uint256 expectedAgentShare = 6_860 ether;

        assertEq(usdc.balanceOf(treasury), expectedPlatformFee);
        assertEq(usdc.balanceOf(alice), expectedAgentShare); // alice is agentWallet
        assertEq(usdc.balanceOf(address(router)), expectedBuyback); // buyback held

        // Check record
        RevenueRouter.RevenueRecord memory record = router.getRevenue(agentId, address(usdc));
        assertEq(record.totalDistributed, amount);
        assertEq(record.buybackAccrued, expectedBuyback);
        assertEq(record.lastDistributionAt, block.timestamp);
    }

    function test_distribute_revertsIfNothingToDistribute() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                RevenueRouter.RevenueRouter__NothingToDistribute.selector, agentId, address(usdc)
            )
        );
        router.distribute(agentId, address(usdc));
    }

    function test_distribute_canBeCalledByAnyone() public {
        uint256 amount = 1_000 ether;

        vm.startPrank(bob);
        usdc.approve(address(router), amount);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();

        // Random address can distribute
        address random = makeAddr("random");
        vm.prank(random);
        router.distribute(agentId, address(usdc));

        // Agent still gets their share
        assertTrue(usdc.balanceOf(alice) > 0);
    }

    function test_distribute_multipleDepositsAndDistributions() public {
        // Deposit 1
        vm.startPrank(bob);
        usdc.approve(address(router), 2_000 ether);
        router.depositRevenue(agentId, address(usdc), 1_000 ether);
        vm.stopPrank();

        router.distribute(agentId, address(usdc));

        uint256 aliceBalAfterFirst = usdc.balanceOf(alice);
        assertTrue(aliceBalAfterFirst > 0);

        // Deposit 2
        vm.startPrank(bob);
        router.depositRevenue(agentId, address(usdc), 1_000 ether);
        vm.stopPrank();

        router.distribute(agentId, address(usdc));

        uint256 aliceBalAfterSecond = usdc.balanceOf(alice);
        // Should get roughly the same agent share as first deposit
        assertApproxEqAbs(aliceBalAfterSecond - aliceBalAfterFirst, aliceBalAfterFirst, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      BUYBACK WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════

    function test_withdrawBuyback_success() public {
        uint256 amount = 10_000 ether;

        vm.startPrank(bob);
        usdc.approve(address(router), amount);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();

        router.distribute(agentId, address(usdc));

        uint256 available = router.getAvailableBuyback(agentId, address(usdc));
        assertTrue(available > 0);

        address buybackDest = makeAddr("buybackDest");
        vm.prank(alice);
        router.withdrawBuybackFunds(agentId, address(usdc), buybackDest);

        assertEq(usdc.balanceOf(buybackDest), available);
        assertEq(router.getAvailableBuyback(agentId, address(usdc)), 0);
    }

    function test_withdrawBuyback_revertsIfNotOwner() public {
        uint256 amount = 1_000 ether;

        vm.startPrank(bob);
        usdc.approve(address(router), amount);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();

        router.distribute(agentId, address(usdc));

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RevenueRouter.RevenueRouter__NotAgentOwner.selector, agentId, bob)
        );
        router.withdrawBuybackFunds(agentId, address(usdc), bob);
    }

    function test_withdrawBuyback_revertsIfNothingToWithdraw() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                RevenueRouter.RevenueRouter__NothingToWithdraw.selector, agentId, address(usdc)
            )
        );
        router.withdrawBuybackFunds(agentId, address(usdc), alice);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function test_getUndistributed() public {
        uint256 amount = 5_000 ether;

        vm.startPrank(bob);
        usdc.approve(address(router), amount);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();

        assertEq(router.getUndistributed(agentId, address(usdc)), amount);

        router.distribute(agentId, address(usdc));
        assertEq(router.getUndistributed(agentId, address(usdc)), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function test_setTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(owner);
        router.setTreasury(newTreasury);

        assertEq(router.treasury(), newTreasury);
    }

    function test_setTreasury_revertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRouter.RevenueRouter__ZeroAddress.selector);
        router.setTreasury(address(0));
    }

    function test_setPlatformFeeBps() public {
        vm.prank(owner);
        router.setPlatformFeeBps(500);
        assertEq(router.platformFeeBps(), 500);
    }

    function test_setPlatformFeeBps_revertsAboveMax() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RevenueRouter.RevenueRouter__FeeTooHigh.selector, 1_001));
        router.setPlatformFeeBps(1_001);
    }

    function test_setBuybackBps() public {
        vm.prank(owner);
        router.setBuybackBps(4_000);
        assertEq(router.buybackBps(), 4_000);
    }

    function test_addRemoveSupportedToken() public {
        address newToken = makeAddr("DAI");

        vm.prank(owner);
        router.addSupportedToken(newToken);
        assertTrue(router.supportedTokens(newToken));

        vm.prank(owner);
        router.removeSupportedToken(newToken);
        assertFalse(router.supportedTokens(newToken));
    }

    function test_addSupportedToken_revertsIfAlreadyAdded() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(RevenueRouter.RevenueRouter__TokenAlreadySupported.selector, address(usdc))
        );
        router.addSupportedToken(address(usdc));
    }

    function test_removeSupportedToken_revertsIfNotSupported() public {
        address random = makeAddr("random");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RevenueRouter.RevenueRouter__TokenNotSupported.selector, random));
        router.removeSupportedToken(random);
    }

    function test_rescueTokens() public {
        // Send some tokens directly to the router (accidental transfer)
        usdc.mint(address(router), 500 ether);

        address dest = makeAddr("rescue");
        vm.prank(owner);
        router.rescueTokens(address(usdc), dest, 500 ether);

        assertEq(usdc.balanceOf(dest), 500 ether);
    }

    function test_rescueTokens_revertsIfNotOwner() public {
        usdc.mint(address(router), 500 ether);

        vm.prank(bob);
        vm.expectRevert();
        router.rescueTokens(address(usdc), bob, 500 ether);
    }

    function test_rescueTokens_revertsOnZeroAddress() public {
        usdc.mint(address(router), 500 ether);

        vm.prank(owner);
        vm.expectRevert(RevenueRouter.RevenueRouter__ZeroAddress.selector);
        router.rescueTokens(address(usdc), address(0), 500 ether);
    }

    function test_pause_unpause() public {
        vm.prank(owner);
        router.pause();

        vm.startPrank(bob);
        usdc.approve(address(router), 100 ether);
        vm.expectRevert();
        router.depositRevenue(agentId, address(usdc), 100 ether);
        vm.stopPrank();

        vm.prank(owner);
        router.unpause();

        vm.startPrank(bob);
        router.depositRevenue(agentId, address(usdc), 100 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                      FUZZ
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_distribute_noRoundingLoss(uint256 amount) public {
        // Bound to reasonable range
        amount = bound(amount, 1 ether, 1_000_000_000 ether);

        usdc.mint(bob, amount);

        vm.startPrank(bob);
        usdc.approve(address(router), amount);
        router.depositRevenue(agentId, address(usdc), amount);
        vm.stopPrank();

        uint256 routerBalBefore = usdc.balanceOf(address(router));

        router.distribute(agentId, address(usdc));

        // Verify: treasury + alice + router buyback == original deposit
        uint256 treasuryBal = usdc.balanceOf(treasury);
        uint256 aliceBal = usdc.balanceOf(alice);
        uint256 routerBal = usdc.balanceOf(address(router));

        assertEq(treasuryBal + aliceBal + routerBal, routerBalBefore);
    }
}
