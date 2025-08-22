// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";

contract DeployTWAPPriceProvider is Script {
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function run() external returns (TWAPPriceProvider) {
        vm.startBroadcast();

        // TWAP interval: 30 minutes (1800 seconds)
        uint32 interval = 1800;

        TWAPPriceProvider.Pair[] memory pairs = new TWAPPriceProvider.Pair[](2);

        // USDC/WETH 0.05% fee (most liquid pool)
        pairs[0] = TWAPPriceProvider.Pair({
            tokenA: USDC,
            tokenB: WETH,
            fee: 500
        });

        // WETH/USDT 0.05% fee
        pairs[1] = TWAPPriceProvider.Pair({
            tokenA: WETH,
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
