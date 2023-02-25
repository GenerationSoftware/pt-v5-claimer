// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { Claimer } from "src/Claimer.sol";
import { ud2x18 } from "prb-math/UD2x18.sol";

import { PrizePoolStub } from "./stub/PrizePoolStub.sol";
import { VaultStub } from "./stub/VaultStub.sol";

contract ClaimerTest is Test {

    uint256 public constant TARGET_PRICE = 0.0001e18;
    uint256 public constant AHEAD1_PRICE = 0.000090909090909090e18;
    uint256 public constant BEHIND1_PRICE = 0.000109999999999999e18;

    Claimer public claimer;
    PrizePoolStub public prizePool;
    VaultStub public vault;

    address winner1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
    address winner2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
    address winner3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
    address winner4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
    address winner5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
    address winner6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

    function setUp() public {
        vm.warp(10 days);
        prizePool = new PrizePoolStub();
        vault = new VaultStub();
        claimer = new Claimer(prizePool, ud2x18(1.1e18), TARGET_PRICE);
    }
 
    function testConstructor() public {
        claimer = new Claimer(prizePool, ud2x18(1e18), TARGET_PRICE);
        assertEq(claimer.decayConstant().unwrap(), 0);
    }

    function testClaimPrizes_empty() public {
        address[] memory winners = new address[](0);
        uint8[] memory tiers = new uint8[](0);
        vm.expectRevert("no winners passed");
        claimer.claimPrizes(vault, winners, tiers, 1, address(this));
    }

    function testClaimPrizes_mismatch() public {
        address[] memory winners = new address[](1);
        uint8[] memory tiers = new uint8[](2);
        vm.expectRevert("data mismatch");
        claimer.claimPrizes(vault, winners, tiers, 1, address(this));
    }

    function testClaimPrizes_insuff() public {
        address[] memory winners = new address[](1);
        winners[0] = winner1;
        uint8[] memory tiers = new uint8[](1);
        tiers[0] = 0;
        // fee should be the target rn
        mockPrizePool(100, 1000, 0, 0);
        vm.expectRevert("insuff fee");
        claimer.claimPrizes(vault, winners, tiers, 1e18, address(this));
    }

    function testClaimPrizes_fees() public {
        address[] memory winners = new address[](2);
        winners[0] = winner1;
        winners[1] = winner2;
        uint8[] memory tiers = new uint8[](2);
        tiers[0] = 1;
        tiers[1] = 1;
        mockPrizePool(1000, 1000, -1, 0);
        uint256 totalFees = TARGET_PRICE + AHEAD1_PRICE;
        mockClaimPrize(winners[0], 1, winners[0], uint96(totalFees/2), address(this), 100);
        mockClaimPrize(winners[1], 1, winners[1], uint96(totalFees/2), address(this), 100);
        uint256 fees = claimer.claimPrizes(vault, winners, tiers, 0.0001e18, address(this));
        assertEq(fees, totalFees);
    }

    function testEstimateFees_zero() public {
        mockPrizePool(1000, 1000, 0, 0);
        assertEq(claimer.estimateFees(0), 0);
    }

    function testEstimateFees_ahead1() public {
        // trying to claim ahead of time
        mockPrizePool(1000, 1000, 0, 0);
        assertEq(claimer.estimateFees(1), AHEAD1_PRICE);
    }

    function testEstimateFees_onTime() public {
        // claiming right on time
        mockPrizePool(1000, 1000, -1, 0);
        assertEq(claimer.estimateFees(1), TARGET_PRICE);
    }

    function testEstimateFees_behind1() public {
        mockPrizePool(1000, 1000, -2, 0);
        assertEq(claimer.estimateFees(1), BEHIND1_PRICE);
    }

    function testEstimateFees_two() public {
        mockPrizePool(1000, 1000, -1, 0);
        assertEq(claimer.estimateFees(2), TARGET_PRICE + AHEAD1_PRICE);
    }

    function mockPrizePool(
        uint256 estimatedPrizeCount,
        uint256 drawPeriodSeconds,
        int256 drawEndedRelativeToNow,
        uint256 claimCount
    ) public {
        vm.mockCall(address(prizePool), abi.encodeWithSignature("estimatedPrizeCount()"), abi.encodePacked(estimatedPrizeCount));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.drawPeriodSeconds.selector), abi.encodePacked(drawPeriodSeconds));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.lastCompletedDrawStartedAt.selector), abi.encodePacked(int256(block.timestamp) - int256(drawPeriodSeconds) + drawEndedRelativeToNow));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.claimCount.selector), abi.encodePacked(claimCount));
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
