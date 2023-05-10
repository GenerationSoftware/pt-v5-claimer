// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { Claimer, Claim } from "src/Claimer.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";

import { PrizePoolStub } from "./stub/PrizePoolStub.sol";
import { VaultStub } from "./stub/VaultStub.sol";
import { LinearVRGDALib } from "src/lib/LinearVRGDALib.sol";

contract ClaimerTest is Test {
    uint256 public constant MINIMUM_FEE = 0.0001e18;
    uint256 public constant MAXIMUM_FEE = 2**128;
    uint256 public constant TIME_TO_REACH_MAX = 86400;
    uint256 public constant ESTIMATED_PRIZES = 1000;
    uint256 public constant SMALLEST_PRIZE_SIZE = 1e18;
    uint256 public constant UNSOLD_100_SECONDS_IN_FEE = 100893106284719;
    uint256 public constant SOLD_ONE_100_SECONDS_IN_FEE = 95351966415391;
    uint64 public constant MAX_FEE_PERCENTAGE_OF_PRIZE = 0.5e18;

    Claimer public claimer;
    PrizePoolStub public prizePool;
    VaultStub public vault;

    SD59x18 public decayConstant;
    uint256 public ahead1_fee; // = 0.000090909090909090e18;

    address winner1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
    address winner2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
    address winner3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
    address winner4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
    address winner5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
    address winner6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

    function setUp() public {
        vm.warp(TIME_TO_REACH_MAX * 100);
        prizePool = new PrizePoolStub();
        vault = new VaultStub();
        claimer = new Claimer(prizePool, MINIMUM_FEE, MAXIMUM_FEE, TIME_TO_REACH_MAX, ud2x18(MAX_FEE_PERCENTAGE_OF_PRIZE));
        decayConstant = LinearVRGDALib.getDecayConstant(LinearVRGDALib.getMaximumPriceDeltaScale(MINIMUM_FEE, MAXIMUM_FEE, TIME_TO_REACH_MAX));
        ahead1_fee = LinearVRGDALib.getVRGDAPrice(MINIMUM_FEE, 0, 1, LinearVRGDALib.getPerTimeUnit(ESTIMATED_PRIZES, TIME_TO_REACH_MAX), decayConstant);
    }

    function testConstructor() public {
        // console2.log("??????? decayConstant", decayConstant.unwrap());
        assertEq(address(claimer.prizePool()), address(prizePool));
        assertEq(claimer.minimumFee(), MINIMUM_FEE);
        assertEq(claimer.decayConstant().unwrap(), decayConstant.unwrap());
    }

    function testClaimPrizes_single() public {
        Claim[] memory claims = new Claim[](1);
        claims[0] = Claim({
            vault: vault,
            winner: winner1,
            tier: 1
        });
        mockPrizePool(1, -100, 0);
        mockClaimPrize(claims[0].winner, 1, claims[0].winner, uint96(UNSOLD_100_SECONDS_IN_FEE), address(this), 100);
        (uint256 claimCount, uint256 totalFees) = claimer.claimPrizes(1, claims, address(this));
        assertEq(claimCount, 1, "Number of prizes claimed");
        assertEq(totalFees, UNSOLD_100_SECONDS_IN_FEE, "Total fees");
    }

    function testClaimPrizes_multiple() public {
        Claim[] memory claims = new Claim[](2);
        claims[0] = Claim({
            vault: vault,
            winner: winner1,
            tier: 1
        });
        claims[1] = Claim({
            vault: vault,
            winner: winner2,
            tier: 1
        });
        mockPrizePool(1, -100, 0);
        mockClaimPrize(claims[0].winner, 1, claims[0].winner, uint96(UNSOLD_100_SECONDS_IN_FEE), address(this), 100);
        mockClaimPrize(claims[1].winner, 1, claims[1].winner, uint96(SOLD_ONE_100_SECONDS_IN_FEE), address(this), 100);
        (uint256 claimCount, uint256 totalFees) = claimer.claimPrizes(1, claims, address(this));
        assertEq(claimCount, 2, "Number of prizes claimed");
        assertEq(totalFees, UNSOLD_100_SECONDS_IN_FEE + SOLD_ONE_100_SECONDS_IN_FEE, "Total fees");
    }

    function testClaimPrizes_maxFee() public {
        Claim[] memory claims = new Claim[](1);
        claims[0] = Claim({
            vault: vault,
            winner: winner1,
            tier: 1
        });
        mockPrizePool(1, -1, 0);
        mockLastCompletedDrawStartedAt(-80000); // much time has passed, meaning the fee is large
        mockClaimPrize(claims[0].winner, 1, claims[0].winner, uint96(0.5e18), address(this), 100);
        (uint256 claimCount, uint256 totalFees) = claimer.claimPrizes(1, claims, address(this));
        assertEq(claimCount, 1, "Number of prizes claimed");
        assertEq(totalFees, 0.5e18, "Total fees");
    }

    function testClaimPrizes_invalidDrawId() public {
        Claim[] memory claims = new Claim[](1);
        claims[0] = Claim({
            vault: vault,
            winner: winner1,
            tier: 1
        });
        mockPrizePool(2, -1, 0);
        mockLastCompletedDrawStartedAt(-80000); // much time has passed, meaning the fee is large
        mockClaimPrize(claims[0].winner, 1, claims[0].winner, uint96(0.5e18), address(this), 100);
        vm.expectRevert(Claimer.DrawInvalid.selector);
        claimer.claimPrizes(1, claims, address(this));
    }

    function testComputeMaxFee() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.calculatePrizeSize.selector, 2), abi.encodePacked(SMALLEST_PRIZE_SIZE));
        assertEq(claimer.computeMaxFee(), 0.5e18);
    }

    function mockPrizePool(
        uint256 drawId,
        int256 drawEndedRelativeToNow,
        uint256 claimCount
    ) public {
        uint numberOfTiers = 2;
        vm.mockCall(address(prizePool), abi.encodeWithSignature("getLastCompletedDrawId()"), abi.encodePacked(drawId));
        vm.mockCall(address(prizePool), abi.encodeWithSignature("estimatedPrizeCount()"), abi.encodePacked(ESTIMATED_PRIZES));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.drawPeriodSeconds.selector), abi.encodePacked(TIME_TO_REACH_MAX));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.numberOfTiers.selector), abi.encodePacked(numberOfTiers));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.calculatePrizeSize.selector, numberOfTiers), abi.encodePacked(SMALLEST_PRIZE_SIZE));
        mockLastCompletedDrawStartedAt(drawEndedRelativeToNow);
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.claimCount.selector), abi.encodePacked(claimCount));
    }

    function mockLastCompletedDrawStartedAt(int256 drawEndedRelativeToNow) public {
        vm.mockCall(
            address(prizePool),
            abi.encodeWithSelector(prizePool.lastCompletedDrawStartedAt.selector),
            abi.encodePacked(int256(block.timestamp) - int256(TIME_TO_REACH_MAX) + drawEndedRelativeToNow)
        );
    }

    function mockClaimPrize(
        address _winner,
        uint8 _tier,
        address _to,
        uint96 _fee,
        address _feeRecipient,
        uint256 _result
    ) public {
        vm.mockCall(address(vault), abi.encodeWithSelector(vault.claimPrize.selector, _winner, _tier, _to, _fee, _feeRecipient), abi.encodePacked(_result));
    }

}
