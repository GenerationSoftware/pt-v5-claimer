// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { UD60x18 } from "prb-math/UD60x18.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { Multicall } from "openzeppelin/utils/Multicall.sol";

import { LinearVRGDALib } from "./libraries/LinearVRGDALib.sol";
import { Vault } from "pt-v5-vault/Vault.sol";

/// @notice Thrown when the length of the winners array does not match the length of the prize indices array while claiming.
/// @param winnersLength Length of the winners array
/// @param prizeIndicesLength Length of the prize indices array
error ClaimArraySizeMismatch(uint256 winnersLength, uint256 prizeIndicesLength);

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

  uint256 public immutable timeToReachMaxFee;

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
    decayConstant = LinearVRGDALib.getDecayConstant(
      LinearVRGDALib.getMaximumPriceDeltaScale(_minimumFee, _maximumFee, _timeToReachMaxFee)
    );
    minimumFee = _minimumFee;
    timeToReachMaxFee = _timeToReachMaxFee;
  }

  /// @notice Allows the call to claim prizes on behalf of others.
  /// @param vault The vault to claim from
  /// @param tier The tier to claim for
  /// @param winners The array of winners to claim for
  /// @param prizeIndices The array of prize indices to claim for each winner (length should match winners)
  /// @param _feeRecipient The address to receive the claim fees
  /// @return totalFees The total fees collected across all successful claims
  function claimPrizes(
    Vault vault,
    uint8 tier,
    address[] calldata winners,
    uint32[][] calldata prizeIndices,
    address _feeRecipient
  ) external returns (uint256 totalFees) {
    if (winners.length != prizeIndices.length) {
      revert ClaimArraySizeMismatch(winners.length, prizeIndices.length);
    }

    uint256 claimCount;
    for (uint i = 0; i < winners.length; i++) {
      claimCount += prizeIndices[i].length;
    }

    uint96 feePerClaim = uint96(
      _computeFeePerClaim(
        _computeMaxFee(tier, prizePool.numberOfTiers()),
        claimCount,
        prizePool.claimCount()
      )
    );

    vault.claimPrizes(tier, winners, prizeIndices, feePerClaim, _feeRecipient);

    return feePerClaim * claimCount;
  }

  /// @notice Computes the total fees for the given number of claims.
  /// @param _tier The tier to claim prizes from
  /// @param _claimCount The number of claims
  /// @return The total fees for those claims
  function computeTotalFees(uint8 _tier, uint _claimCount) external view returns (uint256) {
    return
      _computeFeePerClaim(
        _computeMaxFee(_tier, prizePool.numberOfTiers()),
        _claimCount,
        prizePool.claimCount()
      ) * _claimCount;
  }

  /// @notice Computes the total fees for the given number of claims if a number of claims have already been made.
  /// @param _tier The tier to claim prizes from
  /// @param _claimCount The number of claims
  /// @param _claimedCount The number of prizes already claimed
  /// @return The total fees for those claims
  function computeTotalFees(
    uint8 _tier,
    uint _claimCount,
    uint _claimedCount
  ) external view returns (uint256) {
    return
      _computeFeePerClaim(
        _computeMaxFee(_tier, prizePool.numberOfTiers()),
        _claimCount,
        _claimedCount
      ) * _claimCount;
  }

  /// @notice Computes the fees for several claims.
  /// @param _maxFee the maximum fee that can be charged
  /// @param _claimCount the number of claims to check
  /// @return The fees for the claims
  function computeFeePerClaim(uint256 _maxFee, uint _claimCount) external view returns (uint256) {
    return _computeFeePerClaim(_maxFee, _claimCount, prizePool.claimCount());
  }

  /// @notice Computes the total fees for the given number of claims.
  /// @param _maxFee The maximum fee
  /// @param _claimCount The number of claims to check
  /// @param _claimedCount The number of prizes already claimed
  /// @return The total fees for the claims
  function _computeFeePerClaim(
    uint256 _maxFee,
    uint _claimCount,
    uint _claimedCount
  ) internal view returns (uint256) {
    if (_claimCount == 0) {
      return 0;
    }
    SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(
      prizePool.estimatedPrizeCount(),
      timeToReachMaxFee
    );
    uint256 elapsed = block.timestamp - (prizePool.lastClosedDrawAwardedAt());
    uint256 fee;

    for (uint i = 0; i < _claimCount; i++) {
      fee += _computeFeeForNextClaim(
        minimumFee,
        decayConstant,
        perTimeUnit,
        elapsed,
        _claimedCount + i,
        _maxFee
      );
    }

    return fee / _claimCount;
  }

  /// @notice Computes the maximum fee that can be charged.
  /// @param _tier The tier to compute the max fee for
  /// @return The maximum fee that can be charged
  function computeMaxFee(uint8 _tier) public view returns (uint256) {
    return _computeMaxFee(_tier, prizePool.numberOfTiers());
  }

  /// @notice Computes the max fee given the tier and number of tiers.
  /// @param _tier The tier to compute the max fee for
  /// @param _numTiers The total number of tiers
  /// @return The maximum fee that will be charged for a prize claim for the given tier
  function _computeMaxFee(uint8 _tier, uint8 _numTiers) internal view returns (uint256) {
    uint8 _canaryTier = _numTiers - 1;
    if (_tier != _canaryTier) {
      // canary tier
      return _computeMaxFee(prizePool.getTierPrizeSize(_canaryTier - 1));
    } else {
      return _computeMaxFee(prizePool.getTierPrizeSize(_canaryTier));
    }
  }

  /// @notice Computes the maximum fee that can be charged.
  /// @param _prize The prize to compute the max fee for
  /// @return The maximum fee that can be charged
  function _computeMaxFee(uint256 _prize) internal view returns (uint256) {
    // compute the maximum fee that can be charged
    return UD60x18.unwrap(maxFeePortionOfPrize.intoUD60x18().mul(UD60x18.wrap(_prize)));
  }

  /// @notice Computes the fee for the next claim.
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
    uint256 fee = LinearVRGDALib.getVRGDAPrice(
      _minimumFee,
      _elapsed,
      _sold,
      _perTimeUnit,
      _decayConstant
    );
    return fee > _maxFee ? _maxFee : fee;
  }
}
