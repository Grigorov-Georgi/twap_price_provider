// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {ITWAPPriceProvider} from "./interfaces/ITWAPPriceProvider.sol";
import {UniswapV3PoolManager} from "./UniswapV3PoolManager.sol";

contract TWAPPriceProvider is ITWAPPriceProvider, UniswapV3PoolManager {
    uint32 public immutable twapInterval;

    constructor(address _factory, uint32 _interval, UniswapV3PoolManager.Pair[] memory pairs)
        UniswapV3PoolManager(_factory, pairs)
    {
        require(_interval > 0, "TWAP interval must be > 0");
        twapInterval = _interval;
    }

    /**
     * @notice Gets the TWAP price quote for a token swap
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param fee Pool fee tier to use for the quote
     * @param amountIn Amount of input tokens
     * @return amountOut Expected amount of output tokens based on TWAP
     */
    function consult(address tokenIn, address tokenOut, uint24 fee, uint128 amountIn)
        external
        view
        override
        returns (uint256 amountOut)
    {
        require(tokenIn != tokenOut, "Identical tokens");
        require(amountIn > 0, "Invalid amount");

        address pool = _validatePair(tokenIn, tokenOut, fee);

        (int24 avgTick,) = OracleLibrary.consult(pool, twapInterval);

        amountOut = OracleLibrary.getQuoteAtTick(avgTick, amountIn, tokenIn, tokenOut);
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view override returns (address) {
        (address token0, address token1) = _orderTokens(tokenA, tokenB);
        return allowedPools[token0][token1][fee];
    }
}
