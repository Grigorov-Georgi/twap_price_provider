// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";
import {ITWAPPriceProvider} from "../src/interfaces/ITWAPPriceProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployTWAPPriceProvider} from "../script/DeployTWAPPriceProvider.s.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract TWAPPriceProviderIntegrationTest is Test {
    uint256 public mainnetFork;
    TWAPPriceProvider public priceProvider;
    DeployTWAPPriceProvider public deployer;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    // Mainnet addresses
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Fee tiers
    uint24 constant FEE_LOW = 500; // 0.05%
    uint24 constant FEE_MEDIUM = 3000; // 0.3%
    uint24 constant FEE_HIGH = 10000; // 1%

    uint32 constant TWAP_INTERVAL = 1800; // 30 minutes

    function setUp() public {
        // Create and select the mainnet fork at a specific block for consistent pricing
        // Block 18500000 (October 2023) - ETH ~$1800
        mainnetFork = vm.createFork(MAINNET_RPC_URL, 18500000);
        vm.selectFork(mainnetFork);

        // Deploy using the deploy script
        deployer = new DeployTWAPPriceProvider();
        priceProvider = deployer.run();
    }

    function testConstructorSetsCorrectValues() public view {
        assertEq(priceProvider.uniswapFactory(), UNISWAP_V3_FACTORY);
        assertEq(uint256(priceProvider.twapInterval()), uint256(TWAP_INTERVAL));
    }

    function testPoolsAreRegisteredCorrectly() public view {
        // Check USDC/WETH pool (0.05% fee from deploy script)
        address pool = priceProvider.getPool(USDC, WETH, FEE_LOW);
        assertTrue(pool != address(0), "USDC/WETH pool should be registered");

        // Check WETH/USDT pool (0.05% fee from deploy script)
        pool = priceProvider.getPool(WETH, USDT, FEE_LOW);
        assertTrue(pool != address(0), "WETH/USDT pool should be registered");
    }

    function testConsultWETHToUSDC() public view {
        uint128 amountIn = 1 ether; // 1 WETH

        uint256 amountOut = priceProvider.consult(
            WETH,
            USDC,
            FEE_LOW, // Using FEE_LOW (0.05%) as per deploy script
            amountIn
        );

        assertTrue(amountOut > 0, "Should return positive amount");
        assertTrue(
            amountOut > 1000 * 1e6,
            "1 WETH should be worth more than 1000 USDC"
        );
        assertTrue(
            amountOut < 2000 * 1e6,
            "1 WETH should be worth less than 2000 USDC"
        );
    }

    function testConsultUSDCToWETH() public view {
        uint128 amountIn = 2000 * 1e6; // 2000 USDC

        uint256 amountOut = priceProvider.consult(
            USDC,
            WETH,
            FEE_LOW, // Using FEE_LOW (0.05%) as per deploy script
            amountIn
        );

        assertTrue(amountOut > 0, "Should return positive amount");
        assertTrue(
            amountOut > 1 ether,
            "2000 USDC should be worth more than 1 WETH"
        );
        assertTrue(
            amountOut < 2 ether,
            "2000 USDC should be worth less than 2 WETH"
        );
    }

    function testConsultWETHToUSDT() public view {
        uint128 amountIn = 1 ether; // 1 WETH

        uint256 amountOut = priceProvider.consult(
            WETH,
            USDT,
            FEE_LOW, // Using FEE_LOW (0.05%) as per deploy script
            amountIn
        );

        assertTrue(amountOut > 0, "Should return positive amount");
        assertTrue(
            amountOut > 1000 * 1e6,
            "1 WETH should be worth more than 1000 USDT"
        );
        assertTrue(
            amountOut < 2000 * 1e6,
            "1 WETH should be worth less than 2000 USDT"
        );
    }

    function testConsultUSDTToWETH() public view {
        uint128 amountIn = 2000 * 1e6; // 2000 USDT

        uint256 amountOut = priceProvider.consult(
            USDT,
            WETH,
            FEE_LOW, // Using FEE_LOW (0.05%) as per deploy script
            amountIn
        );

        assertTrue(amountOut > 0, "Should return positive amount");
        assertTrue(
            amountOut > 1 ether,
            "2000 USDT should be worth more than 1 WETH"
        );
        assertTrue(
            amountOut < 2 ether,
            "2000 USDT should be worth less than 2 WETH"
        );
    }

    function testConsultRevertsForIdenticalTokens() public {
        vm.expectRevert("Identical tokens");
        priceProvider.consult(WETH, WETH, FEE_LOW, 1 ether);
    }

    function testConsultRevertsForZeroAmount() public {
        vm.expectRevert("Invalid amount");
        priceProvider.consult(WETH, USDC, FEE_LOW, 0);
    }

    function testConsultRevertsForUnregisteredPair() public {
        vm.expectRevert("Pair not allowed");
        priceProvider.consult(WETH, DAI, FEE_LOW, 1 ether);
    }

    function testConsultRevertsForWrongFee() public {
        vm.expectRevert("Pair not allowed");
        priceProvider.consult(WETH, USDC, FEE_HIGH, 1 ether); // FEE_HIGH not registered
    }

    function testPriceConsistencyBothDirections() public view {
        uint128 amountIn = 1 ether;

        // Get WETH -> USDC price
        uint256 usdcOut = priceProvider.consult(
            WETH,
            USDC,
            FEE_LOW, // Using FEE_LOW as per deploy script
            amountIn
        );

        // Get USDC -> WETH price with the received amount
        uint256 wethOut = priceProvider.consult(
            USDC,
            WETH,
            FEE_LOW, // Using FEE_LOW as per deploy script
            uint128(usdcOut)
        );

        // Due to TWAP and potential price movements, allow some tolerance
        uint256 tolerance = amountIn / 100; // 1% tolerance
        assertTrue(
            wethOut >= amountIn - tolerance && wethOut <= amountIn + tolerance,
            "Round trip should be approximately equal"
        );
    }

    function testMultipleConsultsGiveSameResult() public view {
        uint128 amountIn = 1 ether;

        uint256 result1 = priceProvider.consult(
            WETH,
            USDC,
            FEE_LOW, // Using FEE_LOW as per deploy script
            amountIn
        );
        uint256 result2 = priceProvider.consult(
            WETH,
            USDC,
            FEE_LOW, // Using FEE_LOW as per deploy script
            amountIn
        );
        uint256 result3 = priceProvider.consult(
            WETH,
            USDC,
            FEE_LOW, // Using FEE_LOW as per deploy script
            amountIn
        );

        assertEq(result1, result2, "Multiple calls should return same result");
        assertEq(result2, result3, "Multiple calls should return same result");
    }

    function testTokenOrderingDoesNotMatter() public view {
        uint128 amountIn = 1 ether; // 1 WETH

        // Test WETH -> USDT
        uint256 result1 = priceProvider.consult(WETH, USDT, FEE_LOW, amountIn);

        // Test USDT -> WETH with equivalent amount
        uint256 result2 = priceProvider.consult(
            USDT,
            WETH,
            FEE_LOW,
            uint128(result1)
        );

        // Should be able to convert back with minimal loss
        uint256 tolerance = amountIn / 100; // 1% tolerance
        assertTrue(
            result2 >= amountIn - tolerance && result2 <= amountIn + tolerance,
            "Token ordering should not significantly affect results"
        );
    }
}
