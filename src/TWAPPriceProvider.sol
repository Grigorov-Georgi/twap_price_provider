// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {ITWAPPriceProvider} from "./interfaces/ITWAPPriceProvider.sol";

contract TWAPPriceProvider is ITWAPPriceProvider {
    struct Pair {
        address tokenA;
        address tokenB;
        uint24 fee;
    }

    address public immutable uniswapFactory;
    uint32 public immutable twapInterval;

    mapping(address => mapping(address => mapping(uint24 => address)))
        public
        override getPool;

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

    function _orderTokens(
        address a,
        address b
    ) internal pure returns (address token0, address token1) {
        require(a != b, "Identical tokens");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }
}
