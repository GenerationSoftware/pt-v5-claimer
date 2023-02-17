// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

interface IPrizePool {
    function estimateClaimCount() external returns (uint256);
    function drawPeriodSeconds() external returns (uint256);
    function drawStartedAt() external returns (uint256);
    function claimCount() external returns (uint256);
    function isApprovedClaimer(address _vault, address _claimer) external returns (bool);
}