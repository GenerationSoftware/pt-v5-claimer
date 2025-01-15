// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import { PrizePool, IClaimable, UD2x18, FireFighterClaimer } from "../../src/extensions/FireFighterClaimer.sol";

contract FireFighterClaimerTest is Test {

  event SavedBurningTokens(
    address indexed vault,
    address indexed prizeTokenBurnRecipient,
    address indexed feeRecipient,
    uint256 amountSaved,
    uint256 feeAmount
  );

  event ClaimedPrize(
    address indexed vault,
    address indexed winner,
    address indexed recipient,
    uint24 drawId,
    uint8 tier,
    uint32 prizeIndex,
    uint152 payout,
    uint96 claimReward,
    address claimRewardRecipient
  );

  event WithdrawRewards(
    address indexed account,
    address indexed to,
    uint256 amount,
    uint256 available
  );

  event IncreaseClaimRewards(address indexed to, uint256 amount);

  event Transfer(address indexed from, address indexed to, uint256 amount);

  PrizePool public prizePool = PrizePool(address(0xF35fE10ffd0a9672d0095c435fd8767A7fe29B55));
  uint256 public timeToReachMaxFee = 21600;
  UD2x18 public maxFeePortionOfPrize = UD2x18.wrap(uint64(100000000000000000));
  address public prizeTokenBurnRecipient = address(0xd05Aa5B509105AB1369b213F089198022B0d3e10);
  
  address vaultOwner = address(0x1e0aefca236790179D21f37fa5Fd59a1f00af1Dd);
  address vault = address(0x9B53eF6F13077727D22Cb4ACAD1119c79a97BE17);
  address normalWinner = address(0x3d6fACad1f5c6463E592c94a2a316A7697aD9DE0);
  uint8 winningTier = 5;
  uint32 vaultPrizeIndex = 234;
  uint32 normalWinnerPrizeIndex = 882;

  uint256 fork;
  uint256 forkBlock = 130656944;
  uint256 forkTimestamp = 1736912665;

  FireFighterClaimer public claimer;

  function setUp() public {
    fork = vm.createFork(vm.rpcUrl("optimism"), forkBlock);
    vm.selectFork(fork);
    vm.warp(forkTimestamp);

    claimer = new FireFighterClaimer(
      prizePool,
      timeToReachMaxFee,
      maxFeePortionOfPrize,
      prizeTokenBurnRecipient
    );

    vm.startPrank(vaultOwner);
    vault.call(abi.encodeWithSignature("setClaimer(address)", address(claimer)));
    vm.stopPrank();
  }

  function testClaimWithBurn() external {

    address[] memory winners = new address[](2);
    uint32[][] memory prizeIndices = new uint32[][](2);
    uint32[] memory vaultPrizeIndices = new uint32[](1);
    uint32[] memory normalWinnerPrizeIndices = new uint32[](1);

    winners[0] = vault;
    winners[1] = normalWinner;
    vaultPrizeIndices[0] = vaultPrizeIndex;
    normalWinnerPrizeIndices[0] = normalWinnerPrizeIndex;
    prizeIndices[0] = vaultPrizeIndices;
    prizeIndices[1] = normalWinnerPrizeIndices;

    uint256 prizeSize = 82515613485106;
    uint256 feePerClaim = 560844419929;

    vm.expectEmit();
    emit IncreaseClaimRewards(address(claimer), prizeSize);
    vm.expectEmit();
    emit ClaimedPrize(vault, vault, vault, 271, winningTier, vaultPrizeIndex, 0, uint96(prizeSize), address(claimer));
    vm.expectEmit();
    emit Transfer(address(prizePool), address(claimer), prizeSize);
    vm.expectEmit();
    emit WithdrawRewards(address(claimer), address(claimer), prizeSize, prizeSize);
    vm.expectEmit();
    emit Transfer(address(claimer), address(this), feePerClaim);
    vm.expectEmit();
    emit Transfer(address(claimer), prizeTokenBurnRecipient, prizeSize - feePerClaim);
    vm.expectEmit();
    emit SavedBurningTokens(vault, prizeTokenBurnRecipient, address(this), prizeSize - feePerClaim, feePerClaim);
    vm.expectEmit();
    emit IncreaseClaimRewards(address(this), feePerClaim);
    vm.expectEmit();
    emit ClaimedPrize(vault, normalWinner, normalWinner, 271, winningTier, normalWinnerPrizeIndex, uint152(prizeSize - feePerClaim), uint96(feePerClaim), address(this));
    vm.expectEmit();
    emit Transfer(address(prizePool), normalWinner, prizeSize - feePerClaim);

    claimer.claimPrizes(IClaimable(vault), winningTier, winners, prizeIndices, address(this), 1);

    assertEq(prizePool.prizeToken().balanceOf(prizeTokenBurnRecipient), prizeSize - feePerClaim);
    assertEq(prizePool.prizeToken().balanceOf(address(this)), feePerClaim);
    assertEq(prizePool.rewardBalance(address(this)), feePerClaim);
  }
}