
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IClaimable } from "pt-v5-claimable-interface/interfaces/IClaimable.sol";
import { Claimer } from "../../src/Claimer.sol";

contract ReentrancyMock is IClaimable {

  address public claimer;
  address public badGuy;
  bytes public reentrancyCalldata;

  constructor(address claimer_) {
    claimer = claimer_;
  }

  function claimPrize(
    address _winner,
    uint8 _tier,
    uint32 _prizeIndex,
    uint96 _reward,
    address _rewardRecipient
  ) external returns (uint256) {
    if (_winner == badGuy) {
      (bool success, bytes memory data) = claimer.call(reentrancyCalldata);
      require(success == false, "reentrancy succeeded...");
      assembly {
        revert(add(32, data), mload(data))
      }
    }
    return 1;
  }

  function setReentrancyClaimInfo(
    address _badGuy,
    IClaimable _vault,
    uint8 _tier,
    address[] calldata _winners,
    uint32[][] calldata _prizeIndices,
    address _feeRecipient,
    uint256 _minFeePerClaim
  ) external returns (uint256) {
    badGuy = _badGuy;
    reentrancyCalldata = abi.encodeWithSelector(
      Claimer.claimPrizes.selector,
      _vault,
      _tier,
      _winners,
      _prizeIndices,
      _feeRecipient,
      _minFeePerClaim
    );
  }

}