// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Claimer, IClaimable, PrizePool, UD2x18, SafeCast } from "../Claimer.sol";
import { SafeERC20, IERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract FireFighterClaimer is Claimer {
  using SafeERC20 for IERC20;

  /// @notice Emitted when prize tokens that are about to sent to the vault address are instead redirected to
  /// the `prizeTokenBurnRecipient`.
  /// @param vault The vault that is winning a prize
  /// @param prizeTokenBurnRecipient The recipient of the prize tokens
  /// @param feeRecipient The recipient of the claim fee
  /// @param amountSaved The amount of prize tokens saved from being burned
  /// @param feeAmount The amount of prize tokens sent to the `feeRecipient` directly
  event SavedBurningTokens(
    address indexed vault,
    address indexed prizeTokenBurnRecipient,
    address indexed feeRecipient,
    uint256 amountSaved,
    uint256 feeAmount
  );

  /// The recipient of prize tokens that are won by the prize vault and would otherwise be unretrievable if not redirected
  address public immutable prizeTokenBurnRecipient;

  /// @notice Constructs a new FireFighter Claimer
  /// @param _prizePool The prize pool to claim for
  /// @param _timeToReachMaxFee The time it should take to reach the maximum fee
  /// @param _maxFeePortionOfPrize The maximum fee that can be charged as a portion of the prize size. Fixed point 18 number
  /// @param _prizeTokenBurnRecipient The recipient of prize tokens that are won by the prize vault and would otherwise be unretrievable if not redirected
  constructor(
    PrizePool _prizePool,
    uint256 _timeToReachMaxFee,
    UD2x18 _maxFeePortionOfPrize,
    address _prizeTokenBurnRecipient
  ) Claimer(_prizePool, _timeToReachMaxFee, _maxFeePortionOfPrize) {
    assert(_prizeTokenBurnRecipient != address(0));
    prizeTokenBurnRecipient = _prizeTokenBurnRecipient;
  }

  /// @notice Claims prizes for a batch of winners and prize indices
  /// @dev This function is an override of the default behaviour in order to redirect tokens that are won by the vault
  /// address to the `prizeTokenBurnRecipient` instead, saving them from being lost forever.
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
  ) internal override returns (uint256) {
    uint256 actualClaimCount;
    uint256 prizeIndicesLength;

    // `_winners.length` is not cached cause via-ir would need to be used
    for (uint256 w = 0; w < _winners.length; w++) {
      prizeIndicesLength = _prizeIndices[w].length;
      for (uint256 p = 0; p < prizeIndicesLength; p++) {
        uint256 prizeSize = prizePool.getTierPrizeSize(_tier);
        if (_winners[w] == address(_vault) && _feePerClaim < prizeSize) {
          // Note that we check if `_feePerClaim < prizeSize` to avoid redirecting canary claims that should be
          // sent fully to the fee recipient.

          // Override claim process with fee redirect to save tokens from being burnt. The entire prize will be
          // redirected to this contract and the `_feePerClaim` value will be sent to the `_feeRecipient` directly.
          // Note that this is a BREAKING CHANGE for bots that expect this fee to be claimable from the `prizePool`
          // contract, as is the behaviour on a normal claim. Any remainder value collected by this contract will
          // be sent to the `prizeTokenBurnRecipient`.
          try
            _vault.claimPrize(_winners[w], _tier, _prizeIndices[w][p], SafeCast.toUint96(prizeSize), address(this))
          returns (uint256 /* prizeSize */) {
            actualClaimCount++;
            prizePool.withdrawRewards(address(this), prizeSize);
            IERC20 prizeToken = IERC20(address(prizePool.prizeToken()));
            prizeToken.safeTransfer(_feeRecipient, _feePerClaim);
            uint256 remainder = prizeToken.balanceOf(address(this)); // Get the full remaining balance incase tokens were sent to this address through other means
            prizeToken.safeTransfer(prizeTokenBurnRecipient, remainder);
            emit SavedBurningTokens(address(_vault), prizeTokenBurnRecipient, _feeRecipient, remainder, _feePerClaim);
          } catch (bytes memory reason) {
            emit ClaimError(_vault, _tier, _winners[w], _prizeIndices[w][p], reason);
          }
        } else {
          // Normal claim process
          try
            _vault.claimPrize(_winners[w], _tier, _prizeIndices[w][p], _feePerClaim, _feeRecipient)
          returns (uint256 /* prizeSize */) {
            actualClaimCount++;
          } catch (bytes memory reason) {
            emit ClaimError(_vault, _tier, _winners[w], _prizeIndices[w][p], reason);
          }
        }
      }
    }

    return actualClaimCount;
  }

}