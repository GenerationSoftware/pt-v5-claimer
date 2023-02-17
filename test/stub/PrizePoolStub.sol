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
}