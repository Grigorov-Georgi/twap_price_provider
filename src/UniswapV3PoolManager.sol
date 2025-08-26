// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

abstract contract UniswapV3PoolManager {
    struct Pair {
        address tokenA;
        address tokenB;
        uint24 fee;
    }

    address public immutable uniswapFactory;

    // token0 => token1 => fee => pool
    mapping(address => mapping(address => mapping(uint24 => address)))
        public allowedPools;

    constructor(address factory, Pair[] memory pairs) {
        require(factory != address(0), "Invalid factory");
        require(pairs.length > 0, "No pairs provided");

        uniswapFactory = factory;

        _initializePairs(factory, pairs);
    }

    function _initializePairs(address factory, Pair[] memory pairs) internal {
        for (uint256 i = 0; i < pairs.length; i++) {
            require(
                pairs[i].tokenA != address(0) && pairs[i].tokenB != address(0),
                "Invalid token"
            );
            (address token0, address token1) = _orderTokens(
                pairs[i].tokenA,
                pairs[i].tokenB
            );
            require(
                allowedPools[token0][token1][pairs[i].fee] == address(0),
                "Duplicate pair"
            );

            address pool = IUniswapV3Factory(factory).getPool(
                token0,
                token1,
                pairs[i].fee
            );
            require(pool != address(0), "Pool does not exist");
            allowedPools[token0][token1][pairs[i].fee] = pool;
        }
    }

    function _orderTokens(
        address a,
        address b
    ) internal pure returns (address token0, address token1) {
        require(a != b, "Identical tokens");
        (token0, token1) = a < b ? (a, b) : (b, a);
    }

    function _validatePair(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view returns (address pool) {
        (address token0, address token1) = _orderTokens(tokenA, tokenB);
        pool = allowedPools[token0][token1][fee];
        require(pool != address(0), "Pair not allowed");
    }
}
