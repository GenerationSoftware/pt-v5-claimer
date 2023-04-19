// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

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
    uint256 public immutable targetPrice;
    uint256 public immutable drawPeriodSeconds;

    constructor(
        PrizePool _prizePool,
        UD2x18 _priceDeltaScale,
        uint256 _targetPrice,
        UD2x18 _maxFeePortionOfPrize
    ) {
        prizePool = _prizePool;
        maxFeePortionOfPrize = _maxFeePortionOfPrize;
        decayConstant = LinearVRGDALib.getDecayConstant(_priceDeltaScale);
        targetPrice = _targetPrice;
        drawPeriodSeconds = prizePool.drawPeriodSeconds();
    }

    function claimPrizes(
        uint256 drawId,
        Claim[] calldata _claims,
        address _feeRecipient
    ) external returns (uint256) {
        // first ensure that the draw hasn't changed. If this tx was mined after the draw has changed, then we can't claim anything.
        if (prizePool.lastCompletedDrawId() != drawId) {
            revert DrawInvalid();
        }

        // cache loads
        // uint256 targetPrice_ = targetPrice;
        // SD59x18 decayConstant_ = decayConstant;

        // The below values can change if the draw changes, so we'll cache them then add a protection below to ensure draw id is the same
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(prizePool.estimatedPrizeCount(), drawPeriodSeconds);
        uint256 elapsed = block.timestamp - (prizePool.lastCompletedDrawStartedAt() + drawPeriodSeconds);

        // compute the maximum fee based on the smallest prize size.
        uint256 maxFee = _computeMaxFee();

        uint256 claimCount;
        for (uint i = 0; i < _claims.length; i++) {
            // ensure that the vault didn't complete the draw
            if (prizePool.lastCompletedDrawId() != drawId) {
                revert DrawInvalid();
            }
            uint256 fee = _computeFeeForNextClaim(targetPrice, decayConstant, perTimeUnit, elapsed, prizePool.claimCount(), maxFee);
            if (_claims[i].vault.claimPrize(_claims[i].winner, _claims[i].tier, _claims[i].winner, uint96(fee > maxFee ? maxFee : fee), _feeRecipient) > 0) {
                claimCount++;
            }
        }

        return claimCount;
    }

    function computeMaxFee() external returns (uint256) {
        return _computeMaxFee();
    }

    function _computeMaxFee() internal returns (uint256) {
        // compute the maximum fee that can be charged
        uint256 prize = prizePool.calculatePrizeSize(prizePool.numberOfTiers() - 1);
        return UD60x18.unwrap(maxFeePortionOfPrize.intoUD60x18().mul(UD60x18.wrap(prize)));
    }

    function computeFees(uint256 _claimCount) external returns (uint256) {
        uint256 targetPrice_ = targetPrice;
        SD59x18 decayConstant_ = decayConstant;
        uint256 drawPeriodSeconds = prizePool.drawPeriodSeconds();
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(prizePool.estimatedPrizeCount(), drawPeriodSeconds);
        uint256 elapsed = block.timestamp - (prizePool.lastCompletedDrawStartedAt() + drawPeriodSeconds);
        uint maxFee = _computeMaxFee();
        uint sold = prizePool.claimCount();
        uint fees;
        for (uint i = 0; i <= _claimCount; i++) {
            fees += _computeFeeForNextClaim(targetPrice_, decayConstant_, perTimeUnit, elapsed, sold + i, maxFee);
        }
        return fees;
    }

    function _computeFeeForNextClaim(
        uint256 _targetPrice,
        SD59x18 _decayConstant,
        SD59x18 _perTimeUnit,
        uint256 _elapsed,
        uint256 _sold,
        uint256 _maxFee
    ) internal returns (uint256) {
        uint256 fee = LinearVRGDALib.getVRGDAPrice(_targetPrice, _elapsed, _sold + 1, _perTimeUnit, _decayConstant);
        return fee > _maxFee ? _maxFee : fee;
    }

}
