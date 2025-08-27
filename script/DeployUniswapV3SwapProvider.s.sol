// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {UniswapV3SwapProvider} from "../src/UniswapV3SwapProvider.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";
import {UniswapV3PoolManager} from "../src/UniswapV3PoolManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";
import {DeployTWAPPriceProvider} from "./DeployTWAPPriceProvider.s.sol";

/**
 * @title DeployUniswapV3SwapProvider
 * @notice Deployment script for UniswapV3SwapProvider contract on Ethereum mainnet
 * @dev Deploys with pre-configured USDC/WETH and WETH/USDT pairs using 0.05% fee pools
 */
contract DeployUniswapV3SwapProvider is Script {
    /// @dev Uniswap V3 Factory address on Ethereum mainnet
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    /// @dev Uniswap V3 SwapRouter address on Ethereum mainnet
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /// @dev Wrapped Ether token address on Ethereum mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /// @dev USD Coin token address on Ethereum mainnet
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    /// @dev Tether USD token address on Ethereum mainnet
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /**
     * @notice Deploys the UniswapV3SwapProvider contract with mainnet configuration
     * @param twapPriceProvider Address of deployed TWAPPriceProvider contract
     * @return swapProvider The deployed UniswapV3SwapProvider contract instance
     */
    function run(
        address twapPriceProvider
    ) external returns (UniswapV3SwapProvider) {
        require(
            twapPriceProvider != address(0),
            "Invalid TWAP price provider address"
        );

        vm.startBroadcast();

        // TWAP slippage: 1% (100 basis points)
        uint256 twapSlippageBasisPoints = 100;

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

        pairs[2] = UniswapV3PoolManager.Pair({
            tokenA: USDC,
            tokenB: USDT,
            fee: 500
        });

        UniswapV3SwapProvider swapProvider = new UniswapV3SwapProvider(
            ISwapRouter(SWAP_ROUTER),
            UNISWAP_V3_FACTORY,
            pairs,
            TWAPPriceProvider(twapPriceProvider),
            twapSlippageBasisPoints,
            IWETH9(WETH)
        );

        vm.stopBroadcast();
        return swapProvider;
    }

    /**
     * @notice Deploys both TWAPPriceProvider and UniswapV3SwapProvider in sequence
     * @return swapProvider The deployed UniswapV3SwapProvider contract instance
     */
    function runComplete() external returns (UniswapV3SwapProvider) {
        vm.startBroadcast();

        // First deploy TWAPPriceProvider using existing script
        DeployTWAPPriceProvider twapDeployer = new DeployTWAPPriceProvider();
        TWAPPriceProvider twapProvider = twapDeployer.run();

        // Then deploy UniswapV3SwapProvider
        uint256 twapSlippageBasisPoints = 100; // 1%

        UniswapV3PoolManager.Pair[]
            memory pairs = new UniswapV3PoolManager.Pair[](2);

        pairs[0] = UniswapV3PoolManager.Pair({
            tokenA: USDC,
            tokenB: WETH,
            fee: 500
        });

        pairs[1] = UniswapV3PoolManager.Pair({
            tokenA: WETH,
            tokenB: USDT,
            fee: 500
        });

        UniswapV3SwapProvider swapProvider = new UniswapV3SwapProvider(
            ISwapRouter(SWAP_ROUTER),
            UNISWAP_V3_FACTORY,
            pairs,
            twapProvider,
            twapSlippageBasisPoints,
            IWETH9(WETH)
        );

        vm.stopBroadcast();
        return swapProvider;
    }
}
