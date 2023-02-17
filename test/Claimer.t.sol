// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { Claimer } from "src/Claimer.sol";
import { ud2x18 } from "prb-math/UD2x18.sol";

import { PrizePoolStub } from "./stub/PrizePoolStub.sol";

contract ClaimerTest is Test {

    Claimer public claimer;
    PrizePoolStub public prizePool;

    function setUp() public {
        prizePool = new PrizePoolStub();
        claimer = new Claimer(prizePool, ud2x18(1.1e18), 0.0001e18);
    }

}
