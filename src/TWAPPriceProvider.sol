// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {ITWAPPriceProvider} from "./interfaces/ITWAPPriceProvider.sol";
import {UniswapV3PoolManager} from "./UniswapV3PoolManager.sol";

contract TWAPPriceProvider is ITWAPPriceProvider, UniswapV3PoolManager {
    uint32 private constant _MAX_TWAP_INTERVAL = 9 * 24 * 60 * 60; // 9 days (Uniswap V3 oracle limit)

    constructor(address _factory, UniswapV3PoolManager.Pair[] memory pairs) UniswapV3PoolManager(_factory, pairs) {}

    /**
     * @notice Gets the TWAP price quote for a token swap
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param fee Pool fee tier to use for the quote
     * @param amountIn Amount of input tokens
     * @param interval TWAP interval in seconds
     * @return amountOut Expected amount of output tokens based on TWAP
     */
    function consult(address tokenIn, address tokenOut, uint24 fee, uint128 amountIn, uint32 interval)
        external
        view
        override
        returns (uint256 amountOut)
    {
        require(tokenIn != tokenOut, "Identical tokens");
        require(amountIn > 0, "Invalid amount");
        require(interval > 0, "Invalid interval");
        require(interval <= _MAX_TWAP_INTERVAL, "Interval too long");

        address pool = _validatePair(tokenIn, tokenOut, fee);

        (int24 avgTick,) = OracleLibrary.consult(pool, interval);

        amountOut = OracleLibrary.getQuoteAtTick(avgTick, amountIn, tokenIn, tokenOut);
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view override returns (address) {
        (address token0, address token1) = _orderTokens(tokenA, tokenB);
        return allowedPools[token0][token1][fee];
    }

    function MAX_TWAP_INTERVAL() external pure override returns (uint32) {
        return _MAX_TWAP_INTERVAL;
    }
}
