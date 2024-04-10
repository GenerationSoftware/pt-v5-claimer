// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { UD60x18, convert } from "prb-math/UD60x18.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { LinearVRGDALib } from "./libraries/LinearVRGDALib.sol";
import { IClaimable } from "pt-v5-claimable-interface/interfaces/IClaimable.sol";

/// @notice Thrown when the length of the winners array does not match the length of the prize indices array while claiming.
/// @param winnersLength Length of the winners array
/// @param prizeIndicesLength Length of the prize indices array
error ClaimArraySizeMismatch(uint256 winnersLength, uint256 prizeIndicesLength);

/// @notice Thrown when the VRGDA fee is below the minimum fee
/// @param minFee The minimum fee requested by the user
/// @param fee The actual VRGDA fee
error VrgdaClaimFeeBelowMin(uint256 minFee, uint256 fee);

/// @notice Thrown when the prize pool is set the the zero address
error PrizePoolZeroAddress();

/// @notice Thrown when someone tries to claim a prizes with a fee, but sets the fee recipient address to the zero address.
error FeeRecipientZeroAddress();

/// @notice Thrown when the time to reach the max fee is zero
error TimeToReachMaxFeeZero();

/// @title Variable Rate Gradual Dutch Auction (VRGDA) Claimer
/// @author G9 Software Inc.
/// @notice This contract uses a variable rate gradual dutch auction to incentivize prize claims on behalf of others.  Fees for each canary tier is set to the respective tier's prize size.
contract Claimer {

  /// @notice Emitted when a claim reverts
  /// @param vault The vault for which the claim failed
  /// @param tier The tier for which the claim failed
  /// @param winner The winner for which the claim failed
  /// @param prizeIndex The prize index for which the claim failed
  /// @param reason The revert reason
  event ClaimError(
    IClaimable indexed vault,
    uint8 indexed tier,
    address indexed winner,
    uint32 prizeIndex,
    bytes reason
  );

  /// @notice The Prize Pool that this Claimer is claiming prizes for
  PrizePool public immutable prizePool;

  /// @notice The maximum fee that can be charged as a portion of the prize size. Fixed point 18 number
  UD2x18 public immutable maxFeePortionOfPrize;

  /// @notice The time in seconds to reach the max auction fee
  uint256 public immutable timeToReachMaxFee;

  /// @notice Constructs a new Claimer
  /// @param _prizePool The prize pool to claim for
  /// @param _timeToReachMaxFee The time it should take to reach the maximum fee
  /// @param _maxFeePortionOfPrize The maximum fee that can be charged as a portion of the prize size. Fixed point 18 number
  constructor(
    PrizePool _prizePool,
    uint256 _timeToReachMaxFee,
    UD2x18 _maxFeePortionOfPrize
  ) {
    if (address(0) == address(_prizePool)) {
      revert PrizePoolZeroAddress();
    }
    if (_timeToReachMaxFee == 0) {
      revert TimeToReachMaxFeeZero();
    }
    prizePool = _prizePool;
    maxFeePortionOfPrize = _maxFeePortionOfPrize;
    timeToReachMaxFee = _timeToReachMaxFee;
  }

  /// @notice Allows the caller to claim prizes on behalf of others or for themself.
  /// @dev If you are claiming for yourself or don't want to take a fee, set the `_feeRecipient` and
  /// `_minFeePerClaim` to zero. This will save some gas on fee calculation.
  /// @param _vault The vault to claim from
  /// @param _tier The tier to claim for
  /// @param _winners The array of winners to claim for
  /// @param _prizeIndices The array of prize indices to claim for each winner (length should match winners)
  /// @param _feeRecipient The address to receive the claim fees
  /// @param _minFeePerClaim The minimum fee for each claim
  /// @return totalFees The total fees collected across all successful claims
  function claimPrizes(
    IClaimable _vault,
    uint8 _tier,
    address[] calldata _winners,
    uint32[][] calldata _prizeIndices,
    address _feeRecipient,
    uint256 _minFeePerClaim
  ) external returns (uint256 totalFees) {
    bool feeRecipientZeroAddress = address(0) == _feeRecipient;
    if (feeRecipientZeroAddress && _minFeePerClaim != 0) {
      revert FeeRecipientZeroAddress();
    }
    if (_winners.length != _prizeIndices.length) {
      revert ClaimArraySizeMismatch(_winners.length, _prizeIndices.length);
    }

    uint96 feePerClaim;

    /**
     * If the claimer hasn't specified both a min fee and a fee recipient, we assume that they don't
     * expect a fee and save them some gas on the calculation.
     */
    if (!feeRecipientZeroAddress) {
      feePerClaim = SafeCast.toUint96(_computeFeePerClaim(_tier, _countClaims(_winners, _prizeIndices), prizePool.claimCount()));
      if (feePerClaim < _minFeePerClaim) {
        revert VrgdaClaimFeeBelowMin(_minFeePerClaim, feePerClaim);
      }
    }

    return feePerClaim * _claim(_vault, _tier, _winners, _prizeIndices, _feeRecipient, feePerClaim);
  }

  /// @notice Computes the number of claims that will be made
  /// @param _winners The array of winners to claim for
  /// @param _prizeIndices The array of prize indices to claim for each winner (length should match winners)
  /// @return The number of claims
  function _countClaims(
    address[] calldata _winners,
    uint32[][] calldata _prizeIndices
  ) internal pure returns (uint256) {
    uint256 claimCount;
    uint256 length = _winners.length;
    for (uint256 i = 0; i < length; i++) {
      claimCount += _prizeIndices[i].length;
    }
    return claimCount;
  }

  /// @notice Claims prizes for a batch of winners and prize indices
  /// @param _vault The vault to claim from
  /// @param _tier The tier to claim for
  /// @param _winners The array of winners to claim for
  /// @param _prizeIndices The array of prize indices to claim for each winner (length should match winners)
  /// @param _feeRecipient The address to receive the claim fees
  /// @param _feePerClaim The fee to charge for each claim
  /// @return The number of claims that were successful
  function _claim(
    IClaimable _vault,
    uint8 _tier,
    address[] calldata _winners,
    uint32[][] calldata _prizeIndices,
    address _feeRecipient,
    uint96 _feePerClaim
  ) internal returns (uint256) {
    uint256 actualClaimCount;
    uint256 prizeIndicesLength;

    // `_winners.length` is not cached cause via-ir would need to be used
    for (uint256 w = 0; w < _winners.length; w++) {
      prizeIndicesLength = _prizeIndices[w].length;
      for (uint256 p = 0; p < prizeIndicesLength; p++) {
        try
          _vault.claimPrize(_winners[w], _tier, _prizeIndices[w][p], _feePerClaim, _feeRecipient)
        returns (uint256 /* prizeSize */) {
          actualClaimCount++;
        } catch (bytes memory reason) {
          emit ClaimError(_vault, _tier, _winners[w], _prizeIndices[w][p], reason);
        }
      }
    }

    return actualClaimCount;
  }

  /// @notice Computes the total fees for the given number of claims.
  /// @param _tier The tier to claim prizes from
  /// @param _claimCount The number of claims
  /// @return The total fees for those claims
  function computeTotalFees(uint8 _tier, uint256 _claimCount) external view returns (uint256) {
    return computeTotalFees(_tier, _claimCount, prizePool.claimCount());
  }

  /// @notice Computes the total fees for the given number of claims if a number of claims have already been made.
  /// @param _tier The tier to claim prizes from
  /// @param _claimCount The number of claims
  /// @param _claimedCount The number of prizes already claimed
  /// @return The total fees for those claims
  function computeTotalFees(
    uint8 _tier,
    uint256 _claimCount,
    uint256 _claimedCount
  ) public view returns (uint256) {
    return _computeFeePerClaim(_tier, _claimCount, _claimedCount) * _claimCount;
  }

  /// @notice Computes the fee per claim for the given tier and number of claims
  /// @param _tier The tier to claim prizes from
  /// @param _claimCount The number of claims
  /// @return The fee that will be taken per claim
  function computeFeePerClaim(uint8 _tier, uint256 _claimCount) external view returns (uint256) {
    return _computeFeePerClaim(_tier, _claimCount, prizePool.claimCount());
  }

  /// @notice Computes the total fees for the given number of claims.
  /// @param _tier The tier
  /// @param _claimCount The number of claims to check
  /// @param _claimedCount The number of prizes already claimed
  /// @return The total fees for the claims
  function _computeFeePerClaim(
    uint8 _tier,
    uint256 _claimCount,
    uint256 _claimedCount
  ) internal view returns (uint256) {
    if (_claimCount == 0) {
      return 0;
    }
    if (prizePool.isCanaryTier(_tier)) {
      return prizePool.getTierPrizeSize(_tier);
    }
    uint8 numberOfTiers = prizePool.numberOfTiers();
    uint256 targetFee = _computeFeeTarget(numberOfTiers);
    SD59x18 decayConstant = _computeDecayConstant(targetFee, numberOfTiers);
    uint256 _maxFee = _computeMaxFee(_tier);
    SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(
      prizePool.estimatedPrizeCountWithBothCanaries(),
      timeToReachMaxFee
    );
    uint256 elapsed = block.timestamp - (prizePool.lastAwardedDrawAwardedAt());
    uint256 fee;

    for (uint256 i = 0; i < _claimCount; i++) {
      fee += _computeFeeForNextClaim(
        targetFee,
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
    if (prizePool.isCanaryTier(_tier)) {
      return type(uint256).max; // no limit
    } else {
      return _computeMaxFee(_tier);
    }
  }

  /// @notice Compute the target fee for prize claims
  /// @param _numberOfTiers The current number of tiers for the prize pool
  /// @return The target fee for prize claims
  function _computeFeeTarget(uint8 _numberOfTiers) internal view returns (uint256) {
    // we expect the fee to be somewhere between the first and second canary tier prize sizes,
    // so we set it to the lower of the two.
    return prizePool.getTierPrizeSize(_numberOfTiers - 1);
  }

  /// @notice Computes the decay constant for the VRGDA.
  /// @dev This is a decay constant that ensures the fee will grow from the target to the max fee within the time frame
  /// @param _targetFee The target fee
  /// @param _numberOfTiers The current number of tiers for the prize pool
  /// @return The decay constant
  function _computeDecayConstant(uint256 _targetFee, uint8 _numberOfTiers) internal view returns (SD59x18) {
    // the max fee should never need to go beyond the full daily prize size under normal operating
    // conditions.
    uint maximumFee = prizePool.getTierPrizeSize(_numberOfTiers - 3);
    return LinearVRGDALib.getDecayConstant(
      LinearVRGDALib.getMaximumPriceDeltaScale(
        _targetFee,
        maximumFee,
        timeToReachMaxFee
      )
    );
  }

  /// @notice Computes the max fee given the tier
  /// @param _tier The tier to compute the max fee for
  /// @return The maximum fee that will be charged for a prize claim for the given tier
  function _computeMaxFee(uint8 _tier) internal view returns (uint256) {
    uint256 prizeSize = prizePool.getTierPrizeSize(_tier);
    return
      convert(
        maxFeePortionOfPrize.intoUD60x18().mul(convert(prizeSize))
      );
  }

  /// @notice Computes the fee for the next claim.
  /// @param _targetFee The target fee that should be charged
  /// @param _decayConstant The VRGDA decay constant
  /// @param _perTimeUnit The num to be claimed per second
  /// @param _elapsed The number of seconds that have elapsed
  /// @param _sold The number of prizes that were claimed
  /// @param _maxFee The maximum fee that can be charged
  /// @return The fee to charge for the next claim
  function _computeFeeForNextClaim(
    uint256 _targetFee,
    SD59x18 _decayConstant,
    SD59x18 _perTimeUnit,
    uint256 _elapsed,
    uint256 _sold,
    uint256 _maxFee
  ) internal pure returns (uint256) {
    uint256 fee = LinearVRGDALib.getVRGDAPrice(
      _targetFee,
      _elapsed,
      _sold,
      _perTimeUnit,
      _decayConstant
    );
    return fee > _maxFee ? _maxFee : fee;
  }
}
