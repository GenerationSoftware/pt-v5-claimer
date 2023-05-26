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

/// @title Variable Rate Gradual Dutch Auction (VRGDA) Claimer
/// @author PoolTogether Inc. Team
/// @notice This contract uses a variable rate gradual dutch auction to inventivize prize claims on behalf of others
contract Claimer is Multicall {

    /// @notice Emitted when the passed draw id does not match the Prize Pool's completed draw id
    error DrawInvalid();

    /// @notice The Prize Pool that this Claimer is claiming prizes for
    PrizePool public immutable prizePool;

    /// @notice The maximum fee that can be charged as a portion of the smallest prize size. Fixed point 18 number
    UD2x18 public immutable maxFeePortionOfPrize;

    /// @notice The VRGDA decay constant computed in the constructor
    SD59x18 public immutable decayConstant;

    /// @notice The minimum fee that will be charged
    uint256 public immutable minimumFee;

    /// @notice Constructs a new Claimer
    /// @param _prizePool The prize pool to claim for
    /// @param _minimumFee The minimum fee that should be charged
    /// @param _maximumFee The maximum fee that should be charged
    /// @param _timeToReachMaxFee The time it should take to reach the maximum fee (for example should be the draw period in seconds)
    /// @param _maxFeePortionOfPrize The maximum fee that can be charged as a portion of the smallest prize size. Fixed point 18 number
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

    /// @notice Allows the call to claim prizes on behalf of others.
    /// @param drawId The draw id to claim prizes for
    /// @param _claims The prize claims
    /// @param _feeRecipient The address to receive the claim fees
    /// @return claimCount The number of successful claims
    /// @return totalFees The total fees collected across all successful claims
    function claimPrizes(
        uint256 drawId,
        Claim[] calldata _claims,
        address _feeRecipient
    ) external returns (uint256 claimCount, uint256 totalFees) {

        SD59x18 perTimeUnit;
        uint256 elapsed;
        {
            // The below values can change if the draw changes, so we'll cache them then add a protection below to ensure draw id is the same
            uint256 drawPeriodSeconds = prizePool.drawPeriodSeconds();
            perTimeUnit = LinearVRGDALib.getPerTimeUnit(prizePool.estimatedPrizeCount(), drawPeriodSeconds);
            elapsed = block.timestamp - (prizePool.lastCompletedDrawStartedAt() + drawPeriodSeconds);
        }

        // compute the maximum fee based on the smallest prize size.
        uint256 maxFee = _computeMaxFee();

        for (uint i = 0; i < _claims.length; i++) {
            Claim memory claim = _claims[i];
            // ensure that the vault didn't complete the draw
            if (prizePool.getLastCompletedDrawId() != drawId) {
                revert DrawInvalid();
            }
            uint256 fee = _computeFeeForNextClaim(minimumFee, decayConstant, perTimeUnit, elapsed, prizePool.claimCount() + i, maxFee);
            if (claim.vault.claimPrize(claim.winner, claim.tier, claim.winner, uint96(fee), _feeRecipient) > 0) {
                claimCount++;
                totalFees += fee;
            }
        }
    }

    /// @notice Computes the total fees for the given number of claims
    /// @param _claimCount The number of claims
    /// @return The total fees for those claims
    function computeTotalFees(uint _claimCount) external view returns (uint256) {
        uint256 drawPeriodSeconds = prizePool.drawPeriodSeconds();
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(prizePool.estimatedPrizeCount(), drawPeriodSeconds);
        uint256 elapsed = block.timestamp - (prizePool.lastCompletedDrawStartedAt() + drawPeriodSeconds);
        uint256 maxFee = _computeMaxFee();
        uint256 fee;
        for (uint i = 0; i < _claimCount; i++) {
            fee += _computeFeeForNextClaim(minimumFee, decayConstant, perTimeUnit, elapsed, prizePool.claimCount() + i, maxFee);
        }
        return fee;
    }

    /// @notice Computes the maximum fee that can be charged
    /// @return The maximum fee that can be charged
    function computeMaxFee() external view returns (uint256) {
        return _computeMaxFee();
    }

    /// @notice Computes the maximum fee that can be charged
    /// @return The maximum fee that can be charged
    function _computeMaxFee() internal view returns (uint256) {
        // compute the maximum fee that can be charged
        uint256 prize = prizePool.calculatePrizeSize(prizePool.numberOfTiers());
        return UD60x18.unwrap(maxFeePortionOfPrize.intoUD60x18().mul(UD60x18.wrap(prize)));
    }

    /// @notice Computes the fee for the next claim
    /// @param _minimumFee The minimum fee that should be charged
    /// @param _decayConstant The VRGDA decay constant
    /// @param _perTimeUnit The num to be claimed per second
    /// @param _elapsed The number of seconds that have elapsed
    /// @param _sold The number of prizes that were claimed
    /// @param _maxFee The maximum fee that can be charged
    /// @return The fee to charge for the next claim
    function _computeFeeForNextClaim(
        uint256 _minimumFee,
        SD59x18 _decayConstant,
        SD59x18 _perTimeUnit,
        uint256 _elapsed,
        uint256 _sold,
        uint256 _maxFee
    ) internal pure returns (uint256) {
        uint256 fee = LinearVRGDALib.getVRGDAPrice(_minimumFee, _elapsed, _sold, _perTimeUnit, _decayConstant);
        return fee > _maxFee ? _maxFee : fee;
    }

}
