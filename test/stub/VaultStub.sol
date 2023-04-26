// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { IVault } from "src/interfaces/IVault.sol";

contract VaultStub is IVault {
    function claimPrize(
        address /* _winner */,
        uint8 /* _tier */,
        address /* _to */,
        uint96 /* _fee */,
        address /* _feeRecipient */
    ) external pure override returns (uint256) {
        return 0;
    }
}
