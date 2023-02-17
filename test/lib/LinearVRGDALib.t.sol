// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";

import "src/lib/LinearVRGDALib.sol";

contract LinearVRGDALibTest is Test {

    function testGetPerTimeUnit() public {
        assertEq(LinearVRGDALib.getPerTimeUnit(10, 1000).unwrap(), 0.01e18);
    }

    function testGetDecayConstant() public {
        assertEq(LinearVRGDALib.getDecayConstant(ud2x18(2e18)).unwrap(), 0.693147180559945309e18);
    }

    function testGetVRGDAPrice_atRate() public {
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(1000, 1000);
        SD59x18 decayConstant = LinearVRGDALib.getDecayConstant(ud2x18(1.1e18));
        assertEq(LinearVRGDALib.getVRGDAPrice(0.0001e18, 1, 0, perTimeUnit, decayConstant), 0.0001e18);
    }

    function testGetVRGDAPrice_behind() public {
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(100, 1000);
        SD59x18 decayConstant = LinearVRGDALib.getDecayConstant(ud2x18(1.1e18));
        assertEq(LinearVRGDALib.getVRGDAPrice(0.0001e18, 100, 0, perTimeUnit, decayConstant), 0.531302261184827419e18);
    }

    function testGetVRGDAPrice_ahead() public {
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(1000, 1000);
        SD59x18 decayConstant = LinearVRGDALib.getDecayConstant(ud2x18(1.1e18));
        assertEq(LinearVRGDALib.getVRGDAPrice(0.0001e18, 11, 20, perTimeUnit, decayConstant), 0.000038554328942953e18);
    }

}
