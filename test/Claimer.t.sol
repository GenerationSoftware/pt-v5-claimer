// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import "forge-std/Test.sol";

import {
  Claimer,
  VrgdaClaimFeeBelowMin,
  PrizePoolZeroAddress,
  FeeRecipientZeroAddress,
  TimeToReachMaxFeeZero
} from "../src/Claimer.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";

import { PrizePool, AlreadyClaimed } from "pt-v5-prize-pool/PrizePool.sol";
import { IClaimable } from "pt-v5-claimable-interface/interfaces/IClaimable.sol";
import { LinearVRGDALib } from "../src/libraries/LinearVRGDALib.sol";

// Custom Errors
error ClaimArraySizeMismatch(uint256 winnersLength, uint256 prizeIndicesLength);

contract ClaimerTest is Test {
  event ClaimError(
    IClaimable indexed vault,
    uint8 indexed tier,
    address indexed winner,
    uint32 prizeIndex,
    bytes reason
  );

  uint256 public PRIZE_SIZE_GP = 1000000e18;
  uint256 public PRIZE_SIZE_DAILY = 500e18;
  uint256 public PRIZE_SIZE_C1 = 0.01e18;
  uint256 public PRIZE_SIZE_C2 = 0.0001e18;
  uint256 public TIME_TO_REACH_MAX = 86400;
  uint256 public ESTIMATED_PRIZES = 1000;
  uint256 public NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE = 100243095112994;
  uint256 public SOLD_ONE_100_SECONDS_IN_FEE = 98708714827462;
  uint64 public MAX_FEE_PERCENTAGE_OF_PRIZE = 0.5e18;

  Claimer public claimer;
  PrizePool public prizePool = PrizePool(makeAddr("prizePool"));
  IClaimable public vault = IClaimable(makeAddr("vault"));

  address winner1 = 0x690B9A9E9aa1C9dB991C7721a92d351Db4FaC990;
  address winner2 = 0x4008Ed96594b645f057c9998a2924545fAbB6545;
  address winner3 = 0x796486EBd82E427901511d130Ece93b94f06a980;
  address winner4 = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
  address winner5 = 0x9ebC8E61f87A301fF25a606d7C06150f856F24E2;
  address winner6 = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

  function setUp() public {
    vm.warp(TIME_TO_REACH_MAX * 100);
    vm.etch(address(prizePool), "prizePool");
    vm.etch(address(vault), "fakecode");
    claimer = new Claimer(
      prizePool,
      TIME_TO_REACH_MAX,
      ud2x18(MAX_FEE_PERCENTAGE_OF_PRIZE)
    );
    mockIsCanaryTier(0, false);
    mockIsCanaryTier(1, false);
    mockIsCanaryTier(2, true);
    mockIsCanaryTier(3, true);

    mockGetTierPrizeSize(0, PRIZE_SIZE_GP);
    mockGetTierPrizeSize(1, PRIZE_SIZE_DAILY);
    mockGetTierPrizeSize(2, PRIZE_SIZE_C1);
    mockGetTierPrizeSize(3, PRIZE_SIZE_C2);
  }

  function testConstructor() public {
    assertEq(address(claimer.prizePool()), address(prizePool));
  }

  function testConstructor_TimeToReachMaxFeeZero() public {
    vm.expectRevert(abi.encodeWithSelector(TimeToReachMaxFeeZero.selector));
    new Claimer(
      prizePool, // zero address
      0,
      ud2x18(MAX_FEE_PERCENTAGE_OF_PRIZE)
    );
  }

  function testConstructor_PrizePoolZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(PrizePoolZeroAddress.selector));
    new Claimer(
      PrizePool(address(0)), // zero address
      TIME_TO_REACH_MAX,
      ud2x18(MAX_FEE_PERCENTAGE_OF_PRIZE)
    );
  }

  function testClaimPrizes_ClaimError() public {
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -100, 0);

    vm.mockCallRevert(
      address(vault),
      abi.encodeCall(vault.claimPrize, (winner1, 1, 0, 100243095112994, address(this))),
      "errrooooor"
    );

    vm.expectEmit(true, true, true, true);
    emit ClaimError(vault, 1, winner1, 0, "errrooooor");
    claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
  }

  function testClaimPrizes_FeeRecipientZeroAddress() public {
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -100, 0);
    mockClaimPrize(1, winner1, 0, uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE), address(0), 100);
    vm.expectRevert(abi.encodeWithSelector(FeeRecipientZeroAddress.selector));
    claimer.claimPrizes(vault, 1, winners, prizeIndices, address(0), 1); // zero address with non-zero min fee
  }

  function testClaimPrizes_single() public {
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -100, 0);
    mockClaimPrize(1, winner1, 0, uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE), address(this), 100);
    uint256 totalFees = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
    assertEq(totalFees, NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE, "Total fees");
  }

  function testClaimPrizes_singleNoFeeSavesGas() public {
    // With fee
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -100, 0);
    mockClaimPrize(1, winner1, 0, uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE), address(this), 100);
    uint256 gasBeforeFeeClaim = gasleft();
    uint256 totalFees = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
    uint256 feeClaimGasUsed = gasBeforeFeeClaim - gasleft();
    assertEq(totalFees, NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE, "Total fees");

    // Without fee
    mockPrizePool(1, -100, 0);
    mockClaimPrize(1, winner1, 0, uint96(0), address(0), 0);
    uint256 gasBeforeNoFeeClaim = gasleft();
    uint256 totalNoFeeFees = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(0), 0);
    uint256 noFeeClaimGasUsed = gasBeforeNoFeeClaim - gasleft();
    assertEq(totalNoFeeFees, 0, "Total fees");

    // Check gas
    // console2.log("no fee claim gas savings: ", feeClaimGasUsed - noFeeClaimGasUsed);
    assertGt(feeClaimGasUsed, noFeeClaimGasUsed, "Fee / No Fee Gas Difference");
  }

  function testClaimPrizes_multiple() public {
    address[] memory winners = newWinners(winner1, winner2);
    uint32[][] memory prizeIndices = newPrizeIndices(2, 1);
    mockPrizePool(1, -100, 0);
    mockClaimPrize(
      1,
      winner1,
      0,
      (uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE) + uint96(SOLD_ONE_100_SECONDS_IN_FEE)) / 2,
      address(this),
      100
    );
    mockClaimPrize(
      1,
      winner2,
      0,
      (uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE) + uint96(SOLD_ONE_100_SECONDS_IN_FEE)) / 2,
      address(this),
      100
    );
    uint256 totalFees = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
    assertEq(totalFees, NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE + SOLD_ONE_100_SECONDS_IN_FEE, "Total fees");
  }

  function testClaimPrizes_VrgdaClaimFeeBelowMin() public {
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -100, 0);
    mockClaimPrize(1, winner1, 0, uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE), address(this), 100);
    vm.expectRevert(
      abi.encodeWithSelector(VrgdaClaimFeeBelowMin.selector, 100e18, NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE)
    );
    assertEq(claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 100e18), 0);
  }

  function testClaimPrizes_alreadyClaimedError() public {
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -100, 0);
    vm.mockCallRevert(
      address(vault),
      abi.encodeWithSelector(
        vault.claimPrize.selector,
        winner1,
        1,
        0,
        uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE),
        address(this)
      ),
      abi.encodeWithSelector(AlreadyClaimed.selector, address(vault), winner1, 1, 0)
    );
    vm.expectEmit(true, true, true, true);
    emit ClaimError(vault, 1, winner1, 0, abi.encodeWithSelector(AlreadyClaimed.selector, address(vault), winner1, 1, 0));
    claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
  }

  function testClaimPrizes_maxFee() public {
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -1 * int256((99 * TIME_TO_REACH_MAX) / 100), 0); // much time has passed, meaning the fee is large
    mockClaimPrize(1, winner1, 0, uint96(PRIZE_SIZE_DAILY / 2), address(this), PRIZE_SIZE_DAILY);
    uint256 totalFees = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
    assertEq(totalFees, PRIZE_SIZE_DAILY / 2, "Total fees");
  }

  function testClaimPrizes_veryLongElapsedTime() public {
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -1_000_000, 0);// a long time has passed, meaning the fee should be capped (and there should be no EXP_OVERFLOW!)
    mockClaimPrize(1, winner1, 0, uint96(PRIZE_SIZE_DAILY / 2), address(this), PRIZE_SIZE_DAILY);
    uint256 totalFees = claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
    assertEq(totalFees, PRIZE_SIZE_DAILY / 2, "Total fees");
  }

  function testClaimPrizes_arrayMismatchGt() public {
    // prize indices gt winners
    address[] memory winners = newWinners(winner1);
    uint32[][] memory prizeIndices = newPrizeIndices(2, 1);
    mockPrizePool(1, -100, 0);
    mockClaimPrize(1, winner1, 0, uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE), address(this), 100);
    vm.expectRevert(abi.encodeWithSelector(ClaimArraySizeMismatch.selector, 1, 2));
    claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
  }

  function testClaimPrizes_arrayMismatchLt() public {
    // prize indices lt winners
    address[] memory winners = newWinners(winner1, winner2);
    uint32[][] memory prizeIndices = newPrizeIndices(1, 1);
    mockPrizePool(1, -100, 0);
    mockClaimPrize(1, winner1, 0, uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE), address(this), 100);
    mockClaimPrize(1, winner2, 0, uint96(NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE), address(this), 100);
    vm.expectRevert(abi.encodeWithSelector(ClaimArraySizeMismatch.selector, 2, 1));
    claimer.claimPrizes(vault, 1, winners, prizeIndices, address(this), 0);
  }

  function testComputeTotalFees_zero() public {
    mockPrizePool(1, -100, 0);
    assertEq(claimer.computeTotalFees(1, 0), 0);
  }

  function testComputeTotalFees_one() public {
    mockPrizePool(1, -100, 0);
    assertEq(claimer.computeTotalFees(1, 1), NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE);
  }

  function testComputeTotalFees_two() public {
    mockPrizePool(1, -100, 0);
    uint totalFees = claimer.computeTotalFees(1, 2);
    assertEq(
      totalFees,
      NO_SALES_100_SECONDS_BEHIND_SCHEDULE_FEE + SOLD_ONE_100_SECONDS_IN_FEE
    );
  }

  function testComputeTotalFeesAlreadyClaimed_zero() public {
    mockPrizePool(1, -100, 0);
    assertEq(claimer.computeTotalFees(1, 0, 10), 0);
  }

  function testComputeTotalFeesAlreadyClaimed_one() public {
    mockPrizePool(1, -100, 0);
    assertEq(claimer.computeTotalFees(1, 1, 10), 85914163796254);
  }

  function testComputeTotalFeesAlreadyClaimed_two() public {
    mockPrizePool(1, -100, 0);
    assertEq(claimer.computeTotalFees(1, 2, 10), 170513274430708);
  }

  function testComputeTotalFees_canary() public {
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.claimCount.selector),
      abi.encode(0)
    );
    assertEq(claimer.computeTotalFees(2, 1), PRIZE_SIZE_C1);
  }

  function testComputeMaxFee_normalPrizes() public {
    assertEq(claimer.computeMaxFee(0), PRIZE_SIZE_GP / 2);
    assertEq(claimer.computeMaxFee(1), PRIZE_SIZE_DAILY / 2);
  }

  function testComputeMaxFee_canaryPrizes() public {
    assertEq(claimer.computeMaxFee(2), type(uint256).max); // full size
    assertEq(claimer.computeMaxFee(3), type(uint256).max); // full size
  }

  function testComputeFeePerClaim_minFee() public {
    TIME_TO_REACH_MAX = 1000;
    ESTIMATED_PRIZES = 100;
    uint startTime = block.timestamp;
    uint firstSaleTime = TIME_TO_REACH_MAX / ESTIMATED_PRIZES;
    claimer = new Claimer(
      prizePool,
      TIME_TO_REACH_MAX,
      ud2x18(MAX_FEE_PERCENTAGE_OF_PRIZE)
    );
    mockPrizePool(1, -int(firstSaleTime), 0);
    assertApproxEqAbs(claimer.computeFeePerClaim(0, 1), PRIZE_SIZE_C2, 4);
  }

  function testComputeFeePerClaim_maxFee() public {
    uint startTime = block.timestamp;
    mockPrizePool(1, -100, 0);

    uint firstSaleTime = TIME_TO_REACH_MAX / ESTIMATED_PRIZES;

    vm.warp(startTime + firstSaleTime + TIME_TO_REACH_MAX + 1);
    assertApproxEqRel(claimer.computeFeePerClaim(0, 1), PRIZE_SIZE_DAILY, 0.02e18);
  }

  function mockPrizePool(uint256 drawId, int256 drawEndedRelativeToNow, uint256 claimCount) public {
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSignature("getLastClosedDrawId()"),
      abi.encodePacked(drawId)
    );
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.numberOfTiers.selector),
      abi.encode(4)
    );
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSignature("estimatedPrizeCountWithBothCanaries()"),
      abi.encodePacked(ESTIMATED_PRIZES)
    );
    mockLastClosedDrawAwardedAt(drawEndedRelativeToNow);
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.claimCount.selector),
      abi.encodePacked(claimCount)
    );
  }

  function mockLastClosedDrawAwardedAt(int256 drawEndedRelativeToNow) public {
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.lastAwardedDrawAwardedAt.selector),
      abi.encodePacked(int256(block.timestamp) + drawEndedRelativeToNow)
    );
  }

  function newWinners(address _winner) public view returns (address[] memory) {
    address[] memory winners = new address[](1);
    winners[0] = _winner;
    return winners;
  }

  function newWinners(address _winner1, address _winner2) public view returns (address[] memory) {
    address[] memory winners = new address[](2);
    winners[0] = _winner1;
    winners[1] = _winner2;
    return winners;
  }

  function newPrizeIndices(
    uint32 addressCount,
    uint32 prizeCount
  ) public view returns (uint32[][] memory) {
    uint32[][] memory prizeIndices = new uint32[][](addressCount);
    for (uint256 i = 0; i < addressCount; i++) {
      prizeIndices[i] = new uint32[](prizeCount);
    }
    return prizeIndices;
  }

  function mockClaimPrize(
    uint8 _tier,
    address _winner,
    uint32 _prizeIndex,
    uint96 _fee,
    address _feeRecipient,
    uint256 _result
  ) public {
    vm.mockCall(
      address(vault),
      abi.encodeWithSelector(
        vault.claimPrize.selector,
        _winner,
        _tier,
        _prizeIndex,
        _fee,
        _feeRecipient
      ),
      abi.encodePacked(_result)
    );
  }

  function mockIsCanaryTier(uint8 _tier, bool isCanary) internal {
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.isCanaryTier.selector, _tier),
      abi.encode(isCanary)
    );
  }

  function mockGetTierPrizeSize(uint8 _tier, uint256 prizeSize) internal {
    vm.mockCall(
      address(prizePool),
      abi.encodeWithSelector(prizePool.getTierPrizeSize.selector, _tier),
      abi.encode(prizeSize)
    );
  }
}
