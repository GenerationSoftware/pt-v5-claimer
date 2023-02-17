// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

interface IPrizePool {
    function estimateClaimCount() external returns (uint256);
    function drawPeriodSeconds() external returns (uint256);
    function drawStartedAt() external returns (uint256);
    function claimCount() external returns (uint256);
    function isApprovedClaimer(address _vault, address _claimer) external returns (bool);
    function claimPrize(
        address _winner,
        uint8 _tier,
        address _to,
        uint96 _fee,
        address _feeRecipient
    ) external returns (uint256);
}