// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { wadExp, wadLn, unsafeWadMul, wadDiv } from "solmate/utils/SignedWadMath.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

/// @title Linear Variable Rate Gradual Dutch Auction
/// @author Brendan Asselstine <brendan@g9software.com>
/// @author Original authors FrankieIsLost <frankie@paradigm.xyz> and transmissions11 <t11s@paradigm.xyz>
/// @notice Sell tokens roughly according to an issuance schedule.
library LinearVRGDALib {
  /// @notice Computes the decay constant using the priceDeltaScale
  /// @param _priceDeltaScale The price change per time unit
  /// @return The decay constant
  function getDecayConstant(UD2x18 _priceDeltaScale) internal pure returns (SD59x18) {
    return SD59x18.wrap(wadLn(int256(uint256(_priceDeltaScale.unwrap()))));
  }

  /// @notice Gets the desired number of claims to be sold per second
  /// @param _count The total number of claims
  /// @param _durationSeconds The duration over which claiming should occur
  /// @return The target number of claims per second
  function getPerTimeUnit(
    uint256 _count,
    uint256 _durationSeconds
  ) internal pure returns (SD59x18) {
    return convert(int256(_count)).div(convert(int256(_durationSeconds)));
  }

  /// @notice Calculate the price of a token according to the VRGDA formula
  /// @param _targetPrice The target price of sale scaled by 1e18
  /// @param _timeSinceStart Time passed since the VRGDA began, scaled by 1e18
  /// @param _sold The total number of tokens that have been sold so far
  /// @param _perTimeUnit The target number of claims to sell per second
  /// @param _decayConstant The decay constant for the VRGDA formula
  /// @return The price of a token according to VRGDA, scaled by 1e18
  /// @dev This function has some cases where some calculations might overflow. If an overflow will occur and the calculation would have resulted in a high price, then the max uint256 value is returned. If an overflow would happen where a low price would be returned, then zero is returned.
  function getVRGDAPrice(
    uint256 _targetPrice,
    uint256 _timeSinceStart,
    uint256 _sold,
    SD59x18 _perTimeUnit,
    SD59x18 _decayConstant
  ) internal pure returns (uint256) {
    int256 targetPriceInt = int256(_targetPrice);

    // The division on this line will never overflow if sold is expected to be max 4**15 (max claims at largest tier)
    int256 targetTimeUnwrapped = convert(int256(_timeSinceStart))
      .sub(convert(int256(_sold + 1)).div(_perTimeUnit))
      .unwrap();
    int256 decayConstantUnwrapped = _decayConstant.unwrap();
    unchecked {
      // Check if next multiplication will have overflow. If so, return max uint.
      if (
        targetTimeUnwrapped > 0 && decayConstantUnwrapped > type(int256).max / targetTimeUnwrapped
      ) {
        return type(uint256).max;
      }
      // Check if next multiplication will have a negative overflow. If so, return zero.
      if (
        targetTimeUnwrapped < 0 && decayConstantUnwrapped > type(int256).min / targetTimeUnwrapped
      ) {
        return 0;
      }
      int256 exp = unsafeWadMul(decayConstantUnwrapped, targetTimeUnwrapped);

      // Check if exponent is at the max for the `wadExp` function. If so, limit at max uint.
      if (exp >= 135305999368893231589) {
        return type(uint256).max;
      }
      int256 expResult = wadExp(exp);

      // Return zero if expResult is zero. This prevents zero division later on.
      if (expResult == 0) {
        return 0;
      }

      // If exponential result is greater than 1, then don't worry about extra precision to avoid extra risk of overflow
      if (expResult > 1e18) {
        // Check if multiplication will overflow and return max uint256 if it will.
        if (targetPriceInt > type(int256).max / expResult) {
          return type(uint256).max;
        }
        return uint256(unsafeWadMul(targetPriceInt, expResult));
      } else {
        // Check if multiplication will overflow and return max uint256 if it will.
        int256 extraPrecisionExpResult = int128(expResult * 1e18);
        if (targetPriceInt > type(int256).max / extraPrecisionExpResult) {
          return type(uint256).max;
        }
        return uint256(unsafeWadMul(targetPriceInt, extraPrecisionExpResult)) / 1e18;
      }
    }
  }

  /// @notice Computes the fee delta so that the min fee will reach the max fee in the given time
  /// @param _minFee The fee at the start
  /// @param _maxFee The fee after the time has elapsed
  /// @param _time The elapsed time to reach _maxFee
  /// @return The price delta scale that will ensure the _minFee grows to the _maxFee in _time
  function getMaximumPriceDeltaScale(
    uint256 _minFee,
    uint256 _maxFee,
    uint256 _time
  ) internal pure returns (UD2x18) {
    return
      ud2x18(
        SafeCast.toUint64(
          uint256(
            wadExp(
              wadDiv(
                wadLn(wadDiv(SafeCast.toInt256(_maxFee), SafeCast.toInt256(_minFee))),
                SafeCast.toInt256(_time)
              ) / 1e18
            )
          )
        )
      );
  }
}
