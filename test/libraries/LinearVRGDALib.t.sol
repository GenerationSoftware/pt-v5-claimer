// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";

import "src/libraries/LinearVRGDALib.sol";
import { LinearVRGDALibWrapper } from "test/wrappers/LinearVRGDALibWrapper.sol";

contract LinearVRGDALibTest is Test {
  LinearVRGDALibWrapper wrapper;

  function setUp() public {
    wrapper = new LinearVRGDALibWrapper();
  }

  function testGetPerTimeUnit() public {
    assertEq(wrapper.getPerTimeUnit(10, 1000).unwrap(), 0.01e18);
  }

  function testGetDecayConstant() public {
    assertEq(wrapper.getDecayConstant(ud2x18(2e18)).unwrap(), 0.693147180559945309e18);
  }

  function testGetVRGDAPrice_atRate() public {
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(1000, 1000);
    SD59x18 decayConstant = wrapper.getDecayConstant(ud2x18(1.1e18));
    assertEq(wrapper.getVRGDAPrice(0.0001e18, 1, 0, perTimeUnit, decayConstant), 0.0001e18);
  }

  function testGetVRGDAPrice_behind() public {
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(100, 1000);
    SD59x18 decayConstant = wrapper.getDecayConstant(ud2x18(1.1e18));
    assertEq(
      wrapper.getVRGDAPrice(0.0001e18, 100, 0, perTimeUnit, decayConstant),
      0.531302261184827419e18
    );
  }

  function testGetVRGDAPrice_ahead() public {
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(1000, 1000);
    SD59x18 decayConstant = wrapper.getDecayConstant(ud2x18(1.1e18));
    assertEq(
      wrapper.getVRGDAPrice(0.0001e18, 11, 20, perTimeUnit, decayConstant),
      0.000038554328942953e18
    );
  }

  function testGetVRGDAPrice_overflowExp() public {
    uint32 maxSold = 4 ** 15;
    uint64 maxTime = type(uint64).max;
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(maxSold, maxTime);
    SD59x18 decayConstant = SD59x18.wrap(type(int256).max); // max to test overflow
    assertEq(
      wrapper.getVRGDAPrice(0.0001e18, maxTime, 0, perTimeUnit, decayConstant),
      type(uint256).max
    ); // sold zero at end
  }

  function testGetVRGDAPrice_negOverflowExp() public {
    uint32 maxSold = 4 ** 15;
    uint64 maxTime = type(uint64).max;
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(maxSold, maxTime);
    SD59x18 decayConstant = SD59x18.wrap(type(int256).max); // max to test overflow
    assertEq(wrapper.getVRGDAPrice(0.0001e18, 0, maxSold, perTimeUnit, decayConstant), 0); // sold max at start
  }

  function testGetVRGDAPrice_overflowExpResult() public {
    uint32 maxSold = 4 ** 15;
    uint64 maxTime = type(uint64).max;
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(maxSold, 1);
    SD59x18 decayConstant = wrapper.getDecayConstant(ud2x18(1.1e18));
    assertEq(
      wrapper.getVRGDAPrice(0.0001e18, maxTime, 0, perTimeUnit, decayConstant),
      type(uint256).max
    );
  }

  function testGetVRGDAPrice_expResultZero() public {
    uint32 maxSold = 4 ** 15;
    uint64 maxTime = type(uint64).max;
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(maxSold, maxTime);
    SD59x18 decayConstant = wrapper.getDecayConstant(ud2x18(1.1e18));
    assertEq(wrapper.getVRGDAPrice(0.0001e18, 0, maxSold, perTimeUnit, decayConstant), 0);
  }

  function testGetVRGDAPrice_ahead_priceOverflow() public {
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(1000, 1000);
    SD59x18 decayConstant = wrapper.getDecayConstant(ud2x18(1.1e18));
    assertEq(
      wrapper.getVRGDAPrice(uint256(type(int256).max), 11, 20, perTimeUnit, decayConstant),
      type(uint256).max
    );
  }

  function testGetVRGDAPrice_behind_priceOverflow() public {
    SD59x18 perTimeUnit = wrapper.getPerTimeUnit(1000, 1000);
    SD59x18 decayConstant = wrapper.getDecayConstant(ud2x18(1.1e18));
    assertEq(
      wrapper.getVRGDAPrice(uint256(type(int256).max), 40, 20, perTimeUnit, decayConstant),
      type(uint256).max
    );
  }

  function testGetMaximumPriceDeltaScale() public {
    uint256 maxPrice = 0.03e18;
    uint256 targetPrice = 0.0001e18;
    uint256 maxTime = 86400;
    // maximum number of prizes is 4^15 = 1073741824
    // one day is 86400 seconds
    UD2x18 maxPriceDeltaScale = wrapper.getMaximumPriceDeltaScale(maxPrice, targetPrice, maxTime);

    uint256 price = wrapper.getVRGDAPrice(
      uint256(targetPrice),
      uint256(maxTime),
      0,
      wrapper.getPerTimeUnit(1, 1),
      wrapper.getDecayConstant(maxPriceDeltaScale)
    );

    assertApproxEqAbs(price, uint256(maxPrice), 0.00001e18);
  }
}
