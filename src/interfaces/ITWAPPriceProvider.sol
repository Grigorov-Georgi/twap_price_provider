//SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ITWAPPriceProvider {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address);

    function consult(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint128 amountIn
    ) external view returns (uint256);
}
