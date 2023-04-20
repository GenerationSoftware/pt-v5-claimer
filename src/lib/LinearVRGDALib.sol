// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { UD2x18, ud2x18} from "prb-math/UD2x18.sol";
import { SD59x18, toSD59x18, E } from "prb-math/SD59x18.sol";
import {wadExp, wadLn, wadMul, unsafeWadMul, toWadUnsafe, unsafeWadDiv, wadDiv} from "solmate/utils/SignedWadMath.sol";

/// @title Linear Variable Rate Gradual Dutch Auction
/// @author Brendan Asselstine <brendan@pooltogether.com>
/// @author Original authors FrankieIsLost <frankie@paradigm.xyz> and transmissions11 <t11s@paradigm.xyz>
/// @notice Sell tokens roughly according to an issuance schedule.
library LinearVRGDALib {

    function getDecayConstant(UD2x18 _priceDeltaScale) internal pure returns (SD59x18) {
        return SD59x18.wrap(wadLn(int256(uint256(_priceDeltaScale.unwrap()))));
    }

    function getPerTimeUnit(uint256 _count, uint256 _durationSeconds) internal pure returns (SD59x18) {
        return toSD59x18(int256(_count)).div(toSD59x18(int256(_durationSeconds)));
    }

    /// @notice Calculate the price of a token according to the VRGDA formula.
    /// @param _timeSinceStart Time passed since the VRGDA began, scaled by 1e18.
    /// @param _sold The total number of tokens that have been sold so far.
    /// @return The price of a token according to VRGDA, scaled by 1e18.
    function getVRGDAPrice(uint256 _targetPrice, uint256 _timeSinceStart, uint256 _sold, SD59x18 _perTimeUnit, SD59x18 _decayConstant) internal pure returns (uint256) {
        int256 targetTime = toSD59x18(int256(_timeSinceStart)).sub(toSD59x18(int256(_sold+1)).div(_perTimeUnit)).unwrap();
        unchecked {
            // prettier-ignore
            return uint256(
                wadMul(int256(_targetPrice*1e18), wadExp(unsafeWadMul(_decayConstant.unwrap(), targetTime)
            ))) / 1e18;
        }
    }

    /// @notice Computes the fee delta so that the min fee will reach the max fee in the given time
    /// @param _minFee The fee at the start
    /// @param _maxFee The fee after the time has elapsed
    /// @param _time The elapsed time to reach _maxFee
    /// @return The 
    function getMaximumPriceDeltaScale(uint256 _minFee, uint256 _maxFee, uint256 _time) internal pure returns (UD2x18) {
        int256 div = wadDiv(int256(_maxFee), int256(_minFee));
        int256 ln = wadLn(div);
        int256 maxDiv = wadDiv(ln, int256(_time));
        return ud2x18(uint64(uint256(wadExp(maxDiv/1e18))));
    }
}
