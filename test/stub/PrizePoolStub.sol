// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import { PrizePool } from "v5-prize-pool/PrizePool.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";

contract PrizePoolStub is PrizePool {
    constructor() PrizePool(
        IERC20(address(0)),
        TwabController(address(0)),
        365,
        0,
        0,
        2,
        100,
        10,
        10,
        UD2x18.wrap(0),
        SD1x18.wrap(0)
    ) {
    }
}
