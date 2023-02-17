// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { Claimer } from "src/Claimer.sol";

import { PrizePoolStub } from "./stub/PrizePoolStub.sol";

contract ClaimerTest is Test {

    Claimer public claimer;
    PrizePoolStub public prizePool;

    function setUp() public {
        prizePool = new PrizePoolStub();
        claimer = new Claimer(prizePool);
    }

}
