// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { IPrizePool } from "src/interfaces/IPrizePool.sol";

contract PrizePoolStub is IPrizePool {
    function estimatedPrizeCount() external pure override returns (uint256) {
        return 0;
    }
    function drawPeriodSeconds() external pure override returns (uint256) {
        return 0;
    }
    function lastCompletedDrawStartedAt() external pure override returns (uint256) {
        return 0;
    }
    function claimCount() external pure override returns (uint256) {
        return 0;
    }
}
