// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { UD60x18 } from "prb-math/UD60x18.sol";
import { PrizePool } from "v5-prize-pool/PrizePool.sol";
import { Multicall } from "openzeppelin/utils/Multicall.sol";

import { LinearVRGDALib } from "./lib/LinearVRGDALib.sol";
import { Vault } from "v5-vault/Vault.sol";

/// @title Variable Rate Gradual Dutch Auction (VRGDA) Claimer
/// @author PoolTogether Inc. Team
/// @notice This contract uses a variable rate gradual dutch auction to inventivize prize claims on behalf of others
contract Claimer is Multicall {

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
    /// @param _feeRecipient The address to receive the claim fees
    /// @return totalFees The total fees collected across all successful claims
    function claimPrizes(
        Vault vault,
        uint8 tier,
        address[] calldata winners,
        uint32[][] calldata prizeIndices,
        address _feeRecipient
    ) external returns (uint256 totalFees) {

        uint256 claimCount;
        for (uint i = 0; i < winners.length; i++) {
            claimCount += prizeIndices[i].length;
        }

        // compute the maximum fee based on the smallest prize size.
        uint256 feePerClaim = _computeTotalFees(claimCount) / claimCount;

        vault.claimPrizes(tier, winners, prizeIndices, feePerClaim, _feeRecipient);

        return feePerClaim * claimCount;
    }

    /// @notice Computes the total fees for the given number of claims
    /// @param _claimCount The number of claims
    /// @return The total fees for those claims
    function computeTotalFees(uint _claimCount) external view returns (uint256) {
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(prizePool.estimatedPrizeCount(), prizePool.drawPeriodSeconds());
        uint256 elapsed = block.timestamp - prizePool.lastCompletedDrawAwardedAt();
        uint256 maxFee = _computeMaxFee();
        uint256 fee;

        for (uint i = 0; i < _claimCount; i++) {
            fee += _computeFeeForNextClaim(minimumFee, decayConstant, perTimeUnit, elapsed, prizePool.claimCount() + i, maxFee);
        }

        return (fee / _claimCount) * _claimCount; // round it out to match claimPrizes()
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
