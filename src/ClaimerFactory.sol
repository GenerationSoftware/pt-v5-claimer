// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { Claimer } from "./Claimer.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";

/// @title Claimer Factory
/// @author G9 Software Inc.
/// @notice Factory to deploy new VRGDA Claimer contracts for PoolTogether V5.
contract ClaimerFactory {
  /**
   * @notice Emitted when a new claimer contract is created.
   * @param prizePool The prize pool to claim for
   * @param timeToReachMaxFee The time it should take to reach the maximum fee
   * @param maxFeePortionOfPrize The maximum fee that can be charged as a portion of the prize size. Fixed point 18 number
   */
  event ClaimerCreated(
    Claimer indexed claimer,
    PrizePool indexed prizePool,
    uint256 timeToReachMaxFee,
    UD2x18 maxFeePortionOfPrize
  );

  /* ============ Variables ============ */

  /// @notice List of all claimers deployed by this factory.
  Claimer[] public allClaimers;

  /* ============ Mappings ============ */

  /**
   * @notice Mapping to verify if a Claimer has been deployed via this factory.
   */
  mapping(Claimer claimer => bool deployedFromFactory) public deployedClaimer;

  /**
   * @notice Creates a new Claimer with the provided parameters.
   * @custom:inheritargs Claimer.constructor
   */
  function createClaimer(
    PrizePool _prizePool,
    uint256 _timeToReachMaxFee,
    UD2x18 _maxFeePortionOfPrize
  ) external returns (Claimer) {
    Claimer _claimer = new Claimer(
      _prizePool,
      _timeToReachMaxFee,
      _maxFeePortionOfPrize
    );

    emit ClaimerCreated(
      _claimer,
      _prizePool,
      _timeToReachMaxFee,
      _maxFeePortionOfPrize
    );

    deployedClaimer[_claimer] = true;
    allClaimers.push(_claimer);

    return _claimer;
  }

  /**
   * @notice Total number of claimers deployed by this factory.
   * @return Number of claimers deployed by this factory.
   */
  function totalClaimers() external view returns (uint256) {
    return allClaimers.length;
  }
}
