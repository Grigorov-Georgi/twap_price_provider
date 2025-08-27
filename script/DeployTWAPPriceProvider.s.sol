// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";
import {UniswapV3PoolManager} from "../src/UniswapV3PoolManager.sol";

/**
 * @title DeployTWAPPriceProvider
 * @notice Deployment script for TWAPPriceProvider contract on Ethereum mainnet
 * @dev Deploys with pre-configured USDC/WETH and WETH/USDT pairs using 0.05% fee pools
 */
contract DeployTWAPPriceProvider is Script {
    /// @dev Uniswap V3 Factory address on Ethereum mainnet
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    ///  @dev Wrapped Ether token address on Ethereum mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /// @dev USD Coin token address on Ethereum mainnet
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    /// @dev Tether USD token address on Ethereum mainnet
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /**
     * @notice Deploys the TWAPPriceProvider contract with mainnet configuration
     * @dev Sets up USDC/WETH and WETH/USDT pairs with 30-minute TWAP interval
     * @return priceProvider The deployed TWAPPriceProvider contract instance
     */
    function run() external returns (TWAPPriceProvider) {
        vm.startBroadcast();

        // TWAP interval: 30 minutes (1800 seconds)
        uint32 interval = 1800;

        UniswapV3PoolManager.Pair[]
            memory pairs = new UniswapV3PoolManager.Pair[](3);

        // USDC/WETH 0.05% fee (most liquid pool)
        pairs[0] = UniswapV3PoolManager.Pair({
            tokenA: USDC,
            tokenB: WETH,
            fee: 500
        });

        // WETH/USDT 0.05% fee
        pairs[1] = UniswapV3PoolManager.Pair({
            tokenA: WETH,
            tokenB: USDT,
            fee: 500
        });

        // USDC/USDT 0.05% fee
        pairs[2] = UniswapV3PoolManager.Pair({
            tokenA: USDC,
            tokenB: USDT,
            fee: 500
        });

        TWAPPriceProvider priceProvider = new TWAPPriceProvider(
            UNISWAP_V3_FACTORY,
            interval,
            pairs
        );

        vm.stopBroadcast();
        return priceProvider;
    }
}
