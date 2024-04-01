// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import "forge-std/Test.sol";

import { Claimer } from "../src/Claimer.sol";
import { ClaimerFactory } from "../src/ClaimerFactory.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

contract ClaimerFactoryTest is Test {
  event ClaimerCreated(
    Claimer indexed claimer,
    PrizePool indexed prizePool,
    uint256 timeToReachMaxFee,
    UD2x18 maxFeePortionOfPrize
  );

  PrizePool public prizePool = PrizePool(address(0x1234));
  ClaimerFactory public factory;

  uint256 timeToReachMaxFee = 86400;
  UD2x18 maxFeePortionOfPrize = UD2x18.wrap(0.1e18);

  function setUp() public {
    vm.etch(address(prizePool), "prizePool");
    factory = new ClaimerFactory();
  }

  function testCreateClaimer() external {
    assertEq(factory.totalClaimers(), 0);
    address claimerAddress = address(0x104fBc016F4bb334D775a19E8A6510109AC63E00);
    assertEq(factory.deployedClaimer(Claimer(claimerAddress)), false);

    vm.expectEmit();
    emit ClaimerCreated(
      Claimer(claimerAddress),
      prizePool,
      timeToReachMaxFee,
      maxFeePortionOfPrize
    );
    Claimer claimer = factory.createClaimer(
      prizePool,
      timeToReachMaxFee,
      maxFeePortionOfPrize
    );

    assertEq(address(claimer.prizePool()), address(prizePool));
    assertEq(claimer.timeToReachMaxFee(), timeToReachMaxFee);
    assertEq(claimer.maxFeePortionOfPrize().unwrap(), maxFeePortionOfPrize.unwrap());

    assertEq(claimerAddress, address(claimer));
    assertEq(factory.deployedClaimer(claimer), true);
    assertEq(factory.totalClaimers(), 1);
  }
}
