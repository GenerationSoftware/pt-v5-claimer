// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Claimer.sol";

contract ClaimerTest is Test {
    Claimer public claimer;

    function setUp() public {
        claimer = new Claimer();
    }

}
