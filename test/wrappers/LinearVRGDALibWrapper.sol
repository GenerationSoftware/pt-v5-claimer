// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import { LinearVRGDALib } from "src/libraries/LinearVRGDALib.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";

contract LinearVRGDALibWrapper {
  function getDecayConstant(UD2x18 _priceDeltaScale) external pure returns (SD59x18) {
    SD59x18 result = LinearVRGDALib.getDecayConstant(_priceDeltaScale);
    return result;
  }

  function getPerTimeUnit(
    uint256 _count,
    uint256 _durationSeconds
  ) external pure returns (SD59x18) {
    SD59x18 result = LinearVRGDALib.getPerTimeUnit(_count, _durationSeconds);
    return result;
  }

  function getVRGDAPrice(
    uint256 _targetPrice,
    uint256 _timeSinceStart,
    uint256 _sold,
    SD59x18 _perTimeUnit,
    SD59x18 _decayConstant
  ) external pure returns (uint256) {
    uint256 result = LinearVRGDALib.getVRGDAPrice(
      _targetPrice,
      _timeSinceStart,
      _sold,
      _perTimeUnit,
      _decayConstant
    );
    return result;
  }

  function getMaximumPriceDeltaScale(
    uint256 targetPrice,
    uint256 maxPrice,
    uint256 maxTime
  ) external pure returns (UD2x18) {
    UD2x18 result = LinearVRGDALib.getMaximumPriceDeltaScale(maxPrice, targetPrice, maxTime);
    return result;
  }
}
