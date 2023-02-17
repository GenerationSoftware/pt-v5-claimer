// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { IPrizePool } from "src/interfaces/IPrizePool.sol";

contract PrizePoolStub is IPrizePool {
    function estimateClaimCount() external pure override returns (uint256) {
        return 0;
    }
    function drawPeriodSeconds() external pure override returns (uint256) {
        return 0;
    }
    function drawStartedAt() external pure override returns (uint256) {
        return 0;
    }
    function claimCount() external pure override returns (uint256) {
        return 0;
    }
    function isApprovedClaimer(address _vault, address _claimer) external pure override returns (bool) {
        return false;
    }
    function claimPrize(
        address _winner,
        uint8 _tier,
        address _to,
        uint96 _fee,
        address _feeRecipient
    ) external pure override returns (uint256) {
        return 0;
    }
}