// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { SD59x18 } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";

import { IPrizePool } from "./interfaces/IPrizePool.sol";
import { LinearVRGDALib } from "./lib/LinearVRGDALib.sol";

contract Claimer {

    IPrizePool public immutable prizePool;
    SD59x18 public immutable decayConstant;
    uint256 public immutable targetPrice;

    constructor(IPrizePool _prizePool, UD2x18 _priceDeltaScale, uint256 _targetPrice) {
        prizePool = _prizePool;
        decayConstant = LinearVRGDALib.getDecayConstant(_priceDeltaScale); 
        targetPrice = _targetPrice;
    }

    /***
     * @return Fees earned
     */
    function claim(
        address _vault,
        address[] calldata _winners,
        uint8[] calldata  _tiers,
        uint256 _minFees,
        address _feeRecipient
    ) external returns (uint256) {
        require(prizePool.isApprovedClaimer(_vault, address(this)), "not approved claimer");
        require(_winners.length == _tiers.length, "data mismatch");
        SD59x18 perTimeUnit = LinearVRGDALib.getPerTimeUnit(prizePool.estimateClaimCount(), prizePool.drawPeriodSeconds());
        uint256 sold = prizePool.claimCount();
        uint256 elapsed = block.timestamp - prizePool.drawStartedAt();

        uint256 estimatedFees;
        for (uint i = 0; i < _winners.length; i++) {
            estimatedFees += LinearVRGDALib.getVRGDAPrice(targetPrice, elapsed, sold+i, perTimeUnit, decayConstant);
        }

        require(estimatedFees >= _minFees, "insuff fee");

        uint256 feePerClaim = estimatedFees / _winners.length;
        uint256 actualFees;

        for (uint i = 0; i < _winners.length; i++) {
            if (prizePool.claimPrize(_winners[i], _tiers[i], _winners[i], uint96(feePerClaim), _feeRecipient) != 0) {
                actualFees += feePerClaim;
            }
        }

        return actualFees;
    }

}
