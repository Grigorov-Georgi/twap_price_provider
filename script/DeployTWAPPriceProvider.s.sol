// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";

contract DeployTWAPPriceProvider is Script {
    function run() external returns (TWAPPriceProvider) {
        vm.startBroadcast();

        // Ethereum mainnet Uniswap V3 Factory
        address factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

        // TWAP interval: 30 minutes (1800 seconds)
        uint32 interval = 1800;

        TWAPPriceProvider.Pair[] memory pairs = new TWAPPriceProvider.Pair[](2);

        // USDC/WETH 0.3% fee (most liquid pool)
        pairs[0] = TWAPPriceProvider.Pair({
            tokenA: 0xa0B86991c6218b36c1C19d4a2e9eB0cE3606Eb48, // USDC
            tokenB: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            fee: 3000
        });

        // WETH/USDT 0.3% fee
        pairs[1] = TWAPPriceProvider.Pair({
            tokenA: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            tokenB: 0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
            fee: 3000
        });

        TWAPPriceProvider priceProvider = new TWAPPriceProvider(
            factory,
            interval,
            pairs
        );

        vm.stopBroadcast();
        return priceProvider;
    }
}
