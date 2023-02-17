// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {wadExp, wadLn, wadMul, unsafeWadMul, toWadUnsafe, unsafeWadDiv} from "solmate/utils/SignedWadMath.sol";

/// @title Variable Rate Gradual Dutch Auction
/// @author transmissions11 <t11s@paradigm.xyz>
/// @author FrankieIsLost <frankie@paradigm.xyz>
/// @notice Sell tokens roughly according to an issuance schedule.
library LinearVRGDA {

    function getDecayConstant(int256 _priceDeltaScale) internal view returns (int256) {
        return wadLn(_priceDeltaScale);
    }

    /// @notice Calculate the price of a token according to the VRGDA formula.
    /// @param _timeSinceStart Time passed since the VRGDA began, scaled by 1e18.
    /// @param _sold The total number of tokens that have been sold so far.
    /// @return The price of a token according to VRGDA, scaled by 1e18.
    function getVRGDAPrice(int256 _targetPrice, int256 _timeSinceStart, int256 _sold, int256 _perTimeUnit, int256 _decayConstant) internal view returns (uint256) {
        unchecked {
            // prettier-ignore
            return uint256(wadMul(_targetPrice, wadExp(unsafeWadMul(_decayConstant,
                // Theoretically calling toWadUnsafe with sold can silently overflow but under
                // any reasonable circumstance it will never be large enough. We use sold + 1 as
                // the VRGDA formula's n param represents the nth token and sold is the n-1th token.
                _timeSinceStart - unsafeWadDiv(_sold+1, _perTimeUnit)
            ))));
        }
    }
}