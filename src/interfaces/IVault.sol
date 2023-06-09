// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

interface IVault {

    function claimPrize(
        address _winner,
        uint8 _tier,
        uint96 _fee,
        address _feeRecipient
    ) external returns (uint256);
}