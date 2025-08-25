// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {ITWAPPriceProvider} from "./interfaces/ITWAPPriceProvider.sol";

/**
 * @title TWAPPriceProvider
 * @notice Provides time-weighted average price (TWAP) quotes for token pairs using Uniswap V3 pools
 * @dev This contract allows querying TWAP prices for pre-configured token pairs over a fixed time interval
 */
contract TWAPPriceProvider is ITWAPPriceProvider {
    /**
     * @notice Represents a token pair configuration for TWAP price queries
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param fee Pool fee tier (e.g., 500 for 0.05%, 3000 for 0.3%)
     */
    struct Pair {
        address tokenA;
        address tokenB;
        uint24 fee;
    }

    /// @notice Address of the Uniswap V3 factory contract
    address public immutable uniswapFactory;

    /// @notice Time interval in seconds for TWAP calculation
    uint32 public immutable twapInterval;

    /// @notice Mapping from token0 -> token1 -> fee -> pool address
    mapping(address => mapping(address => mapping(uint24 => address)))
        public
        override getPool;

    /**
     * @notice Initializes the TWAP price provider with factory, interval, and allowed pairs
     * @param _factory Address of the Uniswap V3 factory contract
     * @param _interval Time interval in seconds for TWAP calculation
     * @param pairs Array of token pairs to enable for price queries
     */
    constructor(address _factory, uint32 _interval, Pair[] memory pairs) {
        require(_factory != address(0), "Invalid factory");
        require(_interval > 0, "TWAP interval must be > 0");
        require(pairs.length > 0, "No pairs provided");

        uniswapFactory = _factory;
        twapInterval = _interval;

        for (uint256 i = 0; i < pairs.length; i++) {
            (address token0, address token1) = _orderTokens(
                pairs[i].tokenA,
                pairs[i].tokenB
            );
            require(
                token0 != address(0) && token1 != address(0),
                "Invalid token"
            );
            require(
                getPool[token0][token1][pairs[i].fee] == address(0),
                "Duplicate pair"
            );

            address pool = IUniswapV3Factory(_factory).getPool(
                token0,
                token1,
                pairs[i].fee
            );
            require(pool != address(0), "Pool does not exist");
            getPool[token0][token1][pairs[i].fee] = pool;
        }
    }

    /**
     * @notice Gets the TWAP price quote for a token swap
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param fee Pool fee tier to use for the quote
     * @param amountIn Amount of input tokens
     * @return amountOut Expected amount of output tokens based on TWAP
     */
    function consult(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint128 amountIn
    ) external view override returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "Identical tokens");
        require(amountIn > 0, "Invalid amount");

        (address token0, address token1) = _orderTokens(tokenIn, tokenOut);
        address pool = getPool[token0][token1][fee];
        require(pool != address(0), "Pair not allowed");

        (int24 avgTick, ) = OracleLibrary.consult(pool, twapInterval);

        amountOut = OracleLibrary.getQuoteAtTick(
            avgTick,
            amountIn,
            tokenIn,
            tokenOut
        );
    }

    /**
     * @notice Orders two token addresses according to Uniswap V3 convention (token0 < token1)
     * @param a First token address
     * @param b Second token address
     * @return token0 Lower address (token0)
     * @return token1 Higher address (token1)
     */
    function _orderTokens(
        address a,
        address b
    ) internal pure returns (address token0, address token1) {
        require(a != b, "Identical tokens");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }
}
