// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// import "forge-std/console2.sol";

import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { UD60x18 } from "prb-math/UD60x18.sol";
import { PrizePool } from "v5-prize-pool/PrizePool.sol";
import { Multicall } from "openzeppelin/utils/Multicall.sol";

import { LinearVRGDALib } from "./lib/LinearVRGDALib.sol";
import { IVault } from "./interfaces/IVault.sol";

struct Claim {
    IVault vault;
    address winner;
    uint8 tier;
}

contract Claimer is Multicall {

    error DrawInvalid();

    PrizePool public immutable prizePool;
    UD2x18 public immutable maxFeePortionOfPrize;
    SD59x18 public immutable decayConstant;
    uint256 public immutable minimumFee;

    constructor(
        PrizePool _prizePool,
        uint256 _minimumFee,
        uint256 _maximumFee,
        uint256 _timeToReachMaxFee,
        UD2x18 _maxFeePortionOfPrize
    ) {
        prizePool = _prizePool;
        maxFeePortionOfPrize = _maxFeePortionOfPrize;
        decayConstant = LinearVRGDALib.getDecayConstant(LinearVRGDALib.getMaximumPriceDeltaScale(_minimumFee, _maximumFee, _timeToReachMaxFee));
        minimumFee = _minimumFee;
    }

    function claimPrizes(
        uint256 drawId,
        Claim[] calldata _claims,
        address _feeRecipient
    ) external returns (uint256 claimCount, uint256 totalFees) {
        // console2.log("STARTING....");
        
        // The below values can change if the draw changes, so we'll cache them then add a protection below to ensure draw id is the same
        uint256 drawPeriodSeconds = prizePool.drawPeriodSeconds();
        // console2.log("estimatedPrizeCount", prizePool.estimatedPrizeCount());
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(prizePool.estimatedPrizeCount(), drawPeriodSeconds);
        uint256 elapsed = block.timestamp - (prizePool.lastCompletedDrawStartedAt() + drawPeriodSeconds);
        // console2.log("elapsed", elapsed);

        // compute the maximum fee based on the smallest prize size.
        uint256 maxFee = _computeMaxFee();

        // console2.log("maxFee", maxFee);

        for (uint i = 0; i < _claims.length; i++) {
            // ensure that the vault didn't complete the draw
            if (prizePool.lastCompletedDrawId() != drawId) {
                revert DrawInvalid();
            }
            uint256 fee = _computeFeeForNextClaim(minimumFee, decayConstant, perTimeUnit, elapsed, prizePool.claimCount() + i, maxFee);
            // console2.log("fee", fee);
            // console2.log("winner", _claims[i].winner);
            // console2.log("tier", _claims[i].tier);
            // console2.log("recipient", _claims[i].winner);
            // console2.log("_feeRecipient", _feeRecipient);
            if (_claims[i].vault.claimPrize(_claims[i].winner, _claims[i].tier, _claims[i].winner, uint96(fee), _feeRecipient) > 0) {
                claimCount++;
                totalFees += fee;
            }
        }
    }

    function computeMaxFee() external returns (uint256) {
        return _computeMaxFee();
    }

    function _computeMaxFee() internal returns (uint256) {
        // compute the maximum fee that can be charged
        uint256 prize = prizePool.calculatePrizeSize(prizePool.numberOfTiers() - 1);
        return UD60x18.unwrap(maxFeePortionOfPrize.intoUD60x18().mul(UD60x18.wrap(prize)));
    }

    function _computeFeeForNextClaim(
        uint256 _minimumFee,
        SD59x18 _decayConstant,
        SD59x18 _perTimeUnit,
        uint256 _elapsed,
        uint256 _sold,
        uint256 _maxFee
    ) internal returns (uint256) {
        uint256 fee = LinearVRGDALib.getVRGDAPrice(_minimumFee, _elapsed, _sold, _perTimeUnit, _decayConstant);
        return fee > _maxFee ? _maxFee : fee;
    }

}
