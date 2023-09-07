// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { UD60x18 } from "prb-math/UD60x18.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { Multicall } from "openzeppelin/utils/Multicall.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { LinearVRGDALib } from "./libraries/LinearVRGDALib.sol";
import { Vault } from "pt-v5-vault/Vault.sol";

/// @notice Thrown when the length of the winners array does not match the length of the prize indices array while claiming.
/// @param winnersLength Length of the winners array
/// @param prizeIndicesLength Length of the prize indices array
error ClaimArraySizeMismatch(uint256 winnersLength, uint256 prizeIndicesLength);

/// @notice Emitted when the minimum fee is greater than or equal to the max fee
/// @param minFee The minimum fee passed
/// @param maxFee The maximum fee passed
error MinFeeGeMax(uint256 minFee, uint256 maxFee);

/// @notice Emitted when the VRGDA fee is below the minimum fee
/// @param minFee The minimum fee requested by the user
/// @param fee The actual VRGDA fee
error VrgdaClaimFeeBelowMin(uint256 minFee, uint256 fee);

/// @notice Emitted when the prize pool is set the the zero address
error PrizePoolZeroAddress();

/// @title Variable Rate Gradual Dutch Auction (VRGDA) Claimer
/// @author PoolTogether Inc. Team
/// @notice This contract uses a variable rate gradual dutch auction to inventivize prize claims on behalf of others
contract Claimer is Multicall {

  /// @notice Emitted when a prize has already been claimed
  /// @param winner The winner of the prize
  /// @param tier The prize tier
  /// @param prizeIndex The prize index
  event AlreadyClaimed(
    address winner,
    uint8 tier,
    uint32 prizeIndex
  );

  /// @notice Emitted when a claim reverts
  /// @param vault The vault for which the claim failed
  /// @param tier The tier for which the claim failed
  /// @param winner The winner for which the claim failed
  /// @param prizeIndex The prize index for which the claim failed
  /// @param reason The revert reason
  event ClaimError(
    Vault indexed vault,
    uint8 indexed tier,
    address indexed winner,
    uint32 prizeIndex,
    bytes reason
  );

  /// @notice The Prize Pool that this Claimer is claiming prizes for
  PrizePool public immutable prizePool;

  /// @notice The maximum fee that can be charged as a portion of the prize size. Fixed point 18 number
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
  /// @param _maxFeePortionOfPrize The maximum fee that can be charged as a portion of the prize size. Fixed point 18 number
  constructor(
    PrizePool _prizePool,
    uint256 _minimumFee,
    uint256 _maximumFee,
    uint256 _timeToReachMaxFee,
    UD2x18 _maxFeePortionOfPrize
  ) {
    if (address(0) == address(_prizePool)) {
      revert PrizePoolZeroAddress();
    }
    if (_minimumFee >= _maximumFee) {
      revert MinFeeGeMax(_minimumFee, _maximumFee);
    }
    prizePool = _prizePool;
    maxFeePortionOfPrize = _maxFeePortionOfPrize;
    decayConstant = LinearVRGDALib.getDecayConstant(
      LinearVRGDALib.getMaximumPriceDeltaScale(_minimumFee, _maximumFee, _timeToReachMaxFee)
    );
    minimumFee = _minimumFee;
    timeToReachMaxFee = _timeToReachMaxFee;
  }

  /// @notice Allows the call to claim prizes on behalf of others.
  /// @param _vault The vault to claim from
  /// @param _tier The tier to claim for
  /// @param _winners The array of winners to claim for
  /// @param _prizeIndices The array of prize indices to claim for each winner (length should match winners)
  /// @param _feeRecipient The address to receive the claim fees
  /// @param _minVrgdaFeePerClaim The minimum fee for each claim
  /// @return totalFees The total fees collected across all successful claims
  function claimPrizes(
    Vault _vault,
    uint8 _tier,
    address[] calldata _winners,
    uint32[][] calldata _prizeIndices,
    address _feeRecipient,
    uint256 _minVrgdaFeePerClaim
  ) external returns (uint256 totalFees) {
    if (_winners.length != _prizeIndices.length) {
      revert ClaimArraySizeMismatch(_winners.length, _prizeIndices.length);
    }

    uint96 feePerClaim = SafeCast.toUint96(_computeFeePerClaimForBatch(_tier, _winners, _prizeIndices));

    if (feePerClaim < _minVrgdaFeePerClaim) {
      revert VrgdaClaimFeeBelowMin(_minVrgdaFeePerClaim, feePerClaim);
    }

    return feePerClaim * _claim(
      _vault,
      _tier,
      _winners,
      _prizeIndices,
      _feeRecipient,
      feePerClaim
    );
  }

  /// @notice Computes the fee per claim given a batch of winners and prize indices
  /// @param _tier The tier the claims are for
  /// @param _winners The array of winners to claim for
  /// @param _prizeIndices The array of prize indices to claim for each winner (length should match winners)
  /// @return The fee per claim
  function _computeFeePerClaimForBatch(
    uint8 _tier,
    address[] calldata _winners,
    uint32[][] calldata _prizeIndices
  ) internal view returns (uint256) {
    uint256 claimCount;
    uint256 length = _winners.length;
    for (uint256 i = 0; i < length; i++) {
      claimCount += _prizeIndices[i].length;
    }

    return _computeFeePerClaim(
      _computeMaxFee(_tier),
      claimCount,
      prizePool.claimCount()
    );
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
    Vault _vault,
    uint8 _tier,
    address[] calldata _winners,
    uint32[][] calldata _prizeIndices,
    address _feeRecipient,
    uint96 _feePerClaim
  ) internal returns (uint256) {
    uint256 actualClaimCount;
    for (uint256 w = 0; w < _winners.length; w++) {
      uint256 prizeIndicesLength = _prizeIndices[w].length;
      for (uint256 p = 0; p < prizeIndicesLength; p++) {
        try _vault.claimPrize(
          _winners[w],
          _tier,
          _prizeIndices[w][p],
          _feePerClaim,
          _feeRecipient
        ) returns (uint256 prizeSize) {
          if (0 != prizeSize) {
            actualClaimCount++;
          } else {
            emit AlreadyClaimed(_winners[w], _tier, _prizeIndices[w][p]);
          }
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
    return
      _computeFeePerClaim(
        _computeMaxFee(_tier),
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
    uint256 _claimCount,
    uint256 _claimedCount
  ) external view returns (uint256) {
    return
      _computeFeePerClaim(
        _computeMaxFee(_tier),
        _claimCount,
        _claimedCount
      ) * _claimCount;
  }

  /// @notice Computes the fees for several claims.
  /// @param _maxFee the maximum fee that can be charged
  /// @param _claimCount the number of claims to check
  /// @return The fees for the claims
  function computeFeePerClaim(uint256 _maxFee, uint256 _claimCount) external view returns (uint256) {
    return _computeFeePerClaim(_maxFee, _claimCount, prizePool.claimCount());
  }

  /// @notice Computes the total fees for the given number of claims.
  /// @param _maxFee The maximum fee
  /// @param _claimCount The number of claims to check
  /// @param _claimedCount The number of prizes already claimed
  /// @return The total fees for the claims
  function _computeFeePerClaim(
    uint256 _maxFee,
    uint256 _claimCount,
    uint256 _claimedCount
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

    for (uint256 i = 0; i < _claimCount; i++) {
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
    return _computeMaxFee(_tier);
  }

  /// @notice Computes the max fee given the tier
  /// @param _tier The tier to compute the max fee for
  /// @return The maximum fee that will be charged for a prize claim for the given tier
  function _computeMaxFee(uint8 _tier) internal view returns (uint256) {
    return UD60x18.unwrap(maxFeePortionOfPrize.intoUD60x18().mul(UD60x18.wrap(prizePool.getTierPrizeSize(_tier))));
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
