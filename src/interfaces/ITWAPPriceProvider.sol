//SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ITWAPPriceProvider {
    function MAX_TWAP_INTERVAL() external view returns (uint32);

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);

    function consult(address tokenIn, address tokenOut, uint24 fee, uint128 amountIn, uint32 interval)
        external
        view
        returns (uint256);
}
