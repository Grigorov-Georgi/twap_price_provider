// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {UniswapV3SwapProvider} from "../src/UniswapV3SwapProvider.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployUniswapV3SwapProvider} from "../script/DeployUniswapV3SwapProvider.s.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3SwapProvider} from "../src/interfaces/IUniswapV3SwapProvider.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";
import {UniswapV3PoolManager} from "../src/UniswapV3PoolManager.sol";

contract UniswapV3SwapProviderIntegrationTest is Test {
    uint256 public mainnetFork;
    UniswapV3SwapProvider public swapProvider;
    TWAPPriceProvider public twapProvider;
    DeployUniswapV3SwapProvider public deployer;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    // Test accounts
    address public user;

    // Token contracts
    IERC20 public weth;
    IERC20 public usdc;
    IERC20 public usdt;

    // Mainnet addresses
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Fee tiers
    uint24 constant FEE_LOW = 500; // 0.05%
    uint24 constant FEE_MEDIUM = 3000; // 0.3%
    uint24 constant FEE_HIGH = 10000; // 1%

    uint256 constant UNDER_CURRENT_ETH_VALUE = 4500 * 1e6; // 4500 USDC/USDT
    uint256 constant ABOVE_CURRENT_ETH_VALUE = 5000 * 1e6; // 5000 USDC/USDT

    function setUp() public {
        // Create fork at block 23231874 (end of august 2025) [eth price ~$4600]
        mainnetFork = vm.createFork(MAINNET_RPC_URL, 23231874);
        vm.selectFork(mainnetFork);

        // Set up test accounts
        user = makeAddr("USER");

        // Fund accounts with ETH
        vm.deal(user, 100 ether);

        // Initialize token contracts
        weth = IERC20(MAINNET_WETH);
        usdc = IERC20(MAINNET_USDC);
        usdt = IERC20(MAINNET_USDT);

        // Deploy TWAP provider directly in test context
        UniswapV3PoolManager.Pair[]
            memory twapPairs = new UniswapV3PoolManager.Pair[](3);
        twapPairs[0] = UniswapV3PoolManager.Pair({
            tokenA: MAINNET_USDC,
            tokenB: MAINNET_WETH,
            fee: FEE_LOW
        });
        twapPairs[1] = UniswapV3PoolManager.Pair({
            tokenA: MAINNET_WETH,
            tokenB: MAINNET_USDT,
            fee: FEE_LOW
        });
        twapPairs[2] = UniswapV3PoolManager.Pair({
            tokenA: MAINNET_USDC,
            tokenB: MAINNET_USDT,
            fee: FEE_LOW
        });

        twapProvider = new TWAPPriceProvider(UNISWAP_V3_FACTORY, twapPairs);

        // Deploy swap provider using deployment script with test contract as owner
        deployer = new DeployUniswapV3SwapProvider();
        swapProvider = _deploySwapProviderForTest(address(twapProvider));

        // Deal some tokens to user for testing
        deal(MAINNET_USDC, user, 10000 * 1e6); // 10,000 USDC
        deal(MAINNET_USDT, user, 10000 * 1e6); // 10,000 USDT
        deal(MAINNET_WETH, user, 50 ether); // 50 WETH
    }

    function testConstructorSetsCorrectValues() public view {
        assertEq(swapProvider.uniswapFactory(), UNISWAP_V3_FACTORY);
        assertEq(address(swapProvider.swapRouter()), SWAP_ROUTER);
        assertEq(address(swapProvider.WETH9()), MAINNET_WETH);
        assertEq(
            address(swapProvider.twapPriceProvider()),
            address(twapProvider)
        );
        assertEq(swapProvider.twapSlippageBasisPoints(), 100); // 1%
        assertEq(uint256(swapProvider.twapInterval()), uint256(1800)); // 30 minutes

        assertTrue(
            user.balance >= 100 ether,
            "User should have at least 100 ETH"
        );
        assertTrue(
            usdc.balanceOf(user) >= 10000 * 1e6,
            "User should have at least 10,000 USDC"
        );
        assertTrue(
            usdt.balanceOf(user) >= 10000 * 1e6,
            "User should have at least 10,000 USDT"
        );
        assertTrue(
            weth.balanceOf(user) >= 50 ether,
            "User should have at least 50 WETH"
        );
    }

    function testPoolsAreRegisteredCorrectly() public view {
        address pool = twapProvider.getPool(
            MAINNET_USDC,
            MAINNET_WETH,
            FEE_LOW
        );
        assertTrue(pool != address(0), "USDC/WETH pool should be registered");

        pool = twapProvider.getPool(MAINNET_WETH, MAINNET_USDT, FEE_LOW);
        assertTrue(pool != address(0), "WETH/USDT pool should be registered");
    }

    function testSwapExactInputWETHToUSDC() public {
        vm.startPrank(user);

        uint256 amountIn = 1 ether;
        uint256 deadline = block.timestamp + 300;

        weth.approve(address(swapProvider), amountIn);

        uint256 usdcBalanceBefore = usdc.balanceOf(user);
        uint256 wethBalanceBefore = weth.balanceOf(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        uint256 amountOut = swapProvider.swapExactInput(
            hops,
            amountIn,
            0,
            deadline
        );

        uint256 usdcBalanceAfter = usdc.balanceOf(user);
        uint256 wethBalanceAfter = weth.balanceOf(user);

        assertEq(
            wethBalanceBefore - wethBalanceAfter,
            amountIn,
            "WETH balance should decrease by amountIn"
        );
        assertEq(
            usdcBalanceAfter - usdcBalanceBefore,
            amountOut,
            "USDC balance should increase by amountOut"
        );

        assertTrue(
            amountOut > UNDER_CURRENT_ETH_VALUE,
            "1 WETH should be worth more than 4500 USDC"
        );
        assertTrue(
            amountOut < ABOVE_CURRENT_ETH_VALUE,
            "1 WETH should be worth less than 5000 USDC"
        );

        vm.stopPrank();
    }

    function testSwapExactOutputUSDCToWETH() public {
        vm.startPrank(user);

        uint256 amountOut = 0.5 ether;
        uint256 amountInMaximum = 3000 * 1e6;
        uint256 deadline = block.timestamp + 300;

        usdc.approve(address(swapProvider), amountInMaximum);

        uint256 usdcBalanceBefore = usdc.balanceOf(user);
        uint256 wethBalanceBefore = weth.balanceOf(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_USDC,
            tokenOut: MAINNET_WETH,
            fee: FEE_LOW
        });

        uint256 amountIn = swapProvider.swapExactOutput(
            hops,
            amountOut,
            amountInMaximum,
            deadline
        );

        uint256 usdcBalanceAfter = usdc.balanceOf(user);
        uint256 wethBalanceAfter = weth.balanceOf(user);

        assertEq(
            usdcBalanceBefore - usdcBalanceAfter,
            amountIn,
            "USDC balance should decrease by amountIn"
        );
        assertEq(
            wethBalanceAfter - wethBalanceBefore,
            amountOut,
            "WETH balance should increase by amountOut"
        );

        assertTrue(
            amountIn > UNDER_CURRENT_ETH_VALUE / 2,
            "0.5 WETH should cost more than 2250 USDC"
        );
        assertTrue(amountIn < amountInMaximum, "Should use less than maximum");

        vm.stopPrank();
    }

    function testSwapETHForUSDC() public {
        vm.startPrank(user);

        uint256 ethAmountIn = 1 ether;
        uint256 deadline = block.timestamp + 300;

        uint256 ethBalanceBefore = user.balance;
        uint256 usdcBalanceBefore = usdc.balanceOf(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: address(0), // ETH input
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        uint256 amountOut = swapProvider.swapExactInputNative{
            value: ethAmountIn
        }(hops, 0, deadline);

        uint256 ethBalanceAfter = user.balance;
        uint256 usdcBalanceAfter = usdc.balanceOf(user);

        assertTrue(
            ethBalanceBefore - ethBalanceAfter >= ethAmountIn,
            "ETH should be spent"
        );
        assertEq(
            usdcBalanceAfter - usdcBalanceBefore,
            amountOut,
            "USDC balance should increase"
        );

        assertTrue(
            amountOut > UNDER_CURRENT_ETH_VALUE,
            "1 ETH should be worth more than 4500 USDC"
        );

        vm.stopPrank();
    }

    function testSwapUSDCForWETH() public {
        vm.startPrank(user);

        uint256 amountIn = 3000 * 1e6;
        uint256 deadline = block.timestamp + 300;

        usdc.approve(address(swapProvider), amountIn);

        uint256 wethBalanceBefore = weth.balanceOf(user);
        uint256 usdcBalanceBefore = usdc.balanceOf(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_USDC,
            tokenOut: MAINNET_WETH, // WETH output
            fee: FEE_LOW
        });

        uint256 amountOut = swapProvider.swapExactInput(
            hops,
            amountIn,
            0,
            deadline
        );

        uint256 wethBalanceAfter = weth.balanceOf(user);
        uint256 usdcBalanceAfter = usdc.balanceOf(user);

        assertEq(
            usdcBalanceBefore - usdcBalanceAfter,
            amountIn,
            "USDC should be spent"
        );
        assertEq(
            wethBalanceAfter - wethBalanceBefore,
            amountOut,
            "WETH balance should increase"
        );

        assertTrue(
            amountOut > 0.5 ether,
            "3000 USDC should get more than 0.5 WETH"
        );
        assertTrue(
            amountOut < 1 ether,
            "3000 USDC should get less than 1 WETH"
        );

        vm.stopPrank();
    }

    function testSwapETHForExactUSDC() public {
        vm.startPrank(user);

        uint256 amountOut = 4600 * 1e6;
        uint256 ethMaxIn = 2 ether;
        uint256 deadline = block.timestamp + 300;

        uint256 ethBalanceBefore = user.balance;
        uint256 usdcBalanceBefore = usdc.balanceOf(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: address(0), // ETH input
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        uint256 amountIn = swapProvider.swapExactOutputNative{value: ethMaxIn}(
            hops,
            amountOut,
            deadline
        );

        uint256 ethBalanceAfter = user.balance;
        uint256 usdcBalanceAfter = usdc.balanceOf(user);

        assertEq(
            usdcBalanceAfter - usdcBalanceBefore,
            amountOut,
            "Should receive exact USDC amount"
        );

        assertTrue(amountIn < ethMaxIn, "Should use less than max ETH");
        assertTrue(
            amountIn > 0.5 ether,
            "1500 USDC should cost more than 0.5 ETH"
        );

        uint256 ethSpent = ethBalanceBefore - ethBalanceAfter;
        assertTrue(
            ethSpent >= amountIn,
            "ETH spent should be at least the input amount plus gas costs"
        );

        vm.stopPrank();
    }

    function testSwapRevertsForIdenticalTokens() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_WETH,
            fee: FEE_LOW
        });

        vm.expectRevert("Invalid tokens");
        swapProvider.swapExactInput(hops, 1 ether, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function testSwapRevertsForUnregisteredPair() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: DAI,
            fee: FEE_LOW
        });

        vm.expectRevert("Invalid pool");
        swapProvider.swapExactInput(hops, 1 ether, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function testSwapRevertsForExpiredDeadline() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        vm.expectRevert("Invalid deadline");
        swapProvider.swapExactInput(hops, 1 ether, 0, block.timestamp - 1);
        vm.stopPrank();
    }

    function testETHSwapRevertsWithoutValue() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: address(0),
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        vm.expectRevert("Must send ETH");
        swapProvider.swapExactInputNative(hops, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function testNativeSwapRevertsWithETHOutput() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: address(0),
            tokenOut: address(0),
            fee: FEE_LOW
        });

        vm.expectRevert("Output token must be ERC20");
        swapProvider.swapExactInputNative{value: 1 ether}(
            hops,
            0,
            block.timestamp + 300
        );
        vm.stopPrank();
    }

    function testTWAPSlippageProtection() public {
        vm.startPrank(user);

        uint256 amountIn = 1 ether;
        uint256 deadline = block.timestamp + 300;

        weth.approve(address(swapProvider), amountIn);

        uint256 twapQuote = twapProvider.consult(
            MAINNET_WETH,
            MAINNET_USDC,
            FEE_LOW,
            uint128(amountIn),
            1800
        );

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        uint256 amountOut = swapProvider.swapExactInput(
            hops,
            amountIn,
            0,
            deadline
        );

        uint256 slippageTolerance = (twapQuote * 100) / 10000; // 1% slippage
        assertTrue(
            amountOut >= twapQuote - slippageTolerance,
            "Output should be within slippage tolerance of TWAP"
        );

        vm.stopPrank();
    }

    function testSwapExactInputMultihopWETHToUSDCToUSDT() public {
        vm.startPrank(user);

        uint256 amountIn = 1 ether;
        uint256 deadline = block.timestamp + 300;

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](2);

        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        hops[1] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_USDC,
            tokenOut: MAINNET_USDT,
            fee: FEE_LOW
        });

        weth.approve(address(swapProvider), amountIn);

        uint256 wethBalanceBefore = weth.balanceOf(user);
        uint256 usdtBalanceBefore = usdt.balanceOf(user);

        uint256 amountOut = swapProvider.swapExactInput(
            hops,
            amountIn,
            0, // Auto-calculate minimum output
            deadline
        );

        uint256 wethBalanceAfter = weth.balanceOf(user);
        uint256 usdtBalanceAfter = usdt.balanceOf(user);

        assertEq(
            wethBalanceBefore - wethBalanceAfter,
            amountIn,
            "WETH balance should decrease by amountIn"
        );
        assertEq(
            usdtBalanceAfter - usdtBalanceBefore,
            amountOut,
            "USDT balance should increase by amountOut"
        );

        assertTrue(
            amountOut > UNDER_CURRENT_ETH_VALUE,
            "1 WETH should get more than 4500 USDT"
        );
        assertTrue(
            amountOut < ABOVE_CURRENT_ETH_VALUE,
            "1 WETH should get less than 5000 USDT"
        );

        vm.stopPrank();
    }

    function testSwapExactInputMultihopETHToUSDCToUSDT() public {
        vm.startPrank(user);

        uint256 amountIn = 0.5 ether;
        uint256 deadline = block.timestamp + 300;

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](2);

        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: address(0),
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        hops[1] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_USDC,
            tokenOut: MAINNET_USDT,
            fee: FEE_LOW
        });

        uint256 ethBalanceBefore = user.balance;
        uint256 usdtBalanceBefore = usdt.balanceOf(user);

        uint256 amountOut = swapProvider.swapExactInputNative{value: amountIn}(
            hops,
            0, // Auto-calculate minimum output
            deadline
        );

        uint256 ethBalanceAfter = user.balance;
        uint256 usdtBalanceAfter = usdt.balanceOf(user);

        assertTrue(
            ethBalanceBefore - ethBalanceAfter >= amountIn,
            "ETH balance should decrease by at least amountIn"
        );
        assertEq(
            usdtBalanceAfter - usdtBalanceBefore,
            amountOut,
            "USDT balance should increase by amountOut"
        );

        assertTrue(
            amountOut > UNDER_CURRENT_ETH_VALUE / 2,
            "0.5 ETH should get more than 2250 USDT"
        );
        assertTrue(
            amountOut < ABOVE_CURRENT_ETH_VALUE / 2,
            "0.5 ETH should get less than 2500 USDT"
        );

        vm.stopPrank();
    }

    function testSwapExactOutputMultihopUSDCToWETHToUSDT() public {
        vm.startPrank(user);

        uint256 amountOut = 1000 * 1e6;
        uint256 amountInMaximum = 3000 * 1e6;
        uint256 deadline = block.timestamp + 300;

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](2);

        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_USDC,
            tokenOut: MAINNET_WETH,
            fee: FEE_LOW
        });

        hops[1] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_USDT,
            fee: FEE_LOW
        });

        usdc.approve(address(swapProvider), amountInMaximum);

        uint256 usdcBalanceBefore = usdc.balanceOf(user);
        uint256 usdtBalanceBefore = usdt.balanceOf(user);

        uint256 amountIn = swapProvider.swapExactOutput(
            hops,
            amountOut,
            amountInMaximum,
            deadline
        );

        uint256 usdcBalanceAfter = usdc.balanceOf(user);
        uint256 usdtBalanceAfter = usdt.balanceOf(user);

        assertEq(
            usdcBalanceBefore - usdcBalanceAfter,
            amountIn,
            "USDC balance should decrease by amountIn"
        );
        assertEq(
            usdtBalanceAfter - usdtBalanceBefore,
            amountOut,
            "USDT balance should increase by exact amountOut"
        );

        assertTrue(
            amountIn > 900 * 1e6,
            "Should cost more than 900 USDC for 1000 USDT"
        );
        assertTrue(
            amountIn < 1100 * 1e6,
            "Should cost less than 1100 USDC for 1000 USDT"
        );
        assertTrue(
            amountIn <= amountInMaximum,
            "Should not exceed maximum input"
        );

        vm.stopPrank();
    }

    function testSwapExactOutputMultihopETHToUSDT() public {
        vm.startPrank(user);

        uint256 amountOut = 2000 * 1e6;
        uint256 deadline = block.timestamp + 300;

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);

        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: address(0),
            tokenOut: MAINNET_USDT,
            fee: FEE_LOW
        });

        uint256 ethBalanceBefore = user.balance;
        uint256 usdtBalanceBefore = usdt.balanceOf(user);

        uint256 amountIn = swapProvider.swapExactOutputNative{value: 2 ether}(
            hops,
            amountOut,
            deadline
        );

        uint256 ethBalanceAfter = user.balance;
        uint256 usdtBalanceAfter = usdt.balanceOf(user);

        assertEq(
            usdtBalanceAfter - usdtBalanceBefore,
            amountOut,
            "USDT balance should increase by exact amountOut"
        );

        assertTrue(
            amountIn < 1 ether,
            "Should cost less than 1 ETH for 2000 USDT"
        );
        assertTrue(
            amountIn > 0.3 ether,
            "Should cost more than 0.3 ETH for 2000 USDT"
        );

        uint256 totalEthSpent = ethBalanceBefore - ethBalanceAfter;
        assertTrue(
            totalEthSpent >= amountIn,
            "Total ETH spent should be at least amountIn plus gas"
        );

        vm.stopPrank();
    }

    function testMultihopRevertsForEmptyHops() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory emptyHops = new IUniswapV3SwapProvider.SwapHop[](0);

        vm.expectRevert("At least 1 hop required");
        swapProvider.swapExactInput(
            emptyHops,
            1 ether,
            0,
            block.timestamp + 300
        );

        vm.expectRevert("At least 1 hop required");
        swapProvider.swapExactOutput(
            emptyHops,
            1000 * 1e6,
            2000 * 1e6,
            block.timestamp + 300
        );

        vm.stopPrank();
    }

    function testMultihopRevertsForInvalidPool() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);

        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_USDC,
            fee: 1234 // Invalid fee tier
        });

        vm.expectRevert("Invalid pool");
        swapProvider.swapExactInput(hops, 1 ether, 0, block.timestamp + 300);

        vm.stopPrank();
    }

    function testMultihopRevertsForIdenticalTokens() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);

        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_WETH,
            fee: FEE_LOW
        });

        vm.expectRevert("Invalid tokens");
        swapProvider.swapExactInput(hops, 1 ether, 0, block.timestamp + 300);

        vm.stopPrank();
    }

    function testMultihopRevertsForExpiredDeadline() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);

        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: MAINNET_WETH,
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        vm.expectRevert("Invalid deadline");
        swapProvider.swapExactInput(hops, 1 ether, 0, block.timestamp - 1);

        vm.stopPrank();
    }

    function testMultihopETHSwapRevertsWithoutValue() public {
        vm.startPrank(user);

        IUniswapV3SwapProvider.SwapHop[]
            memory hops = new IUniswapV3SwapProvider.SwapHop[](1);
        hops[0] = IUniswapV3SwapProvider.SwapHop({
            tokenIn: address(0),
            tokenOut: MAINNET_USDC,
            fee: FEE_LOW
        });

        vm.expectRevert("Must send ETH");
        swapProvider.swapExactInputNative(hops, 0, block.timestamp + 300);

        vm.stopPrank();
    }

    function testSetTwapSlippageAsOwner() public {
        // Test setting new slippage as owner
        uint256 newSlippage = 200; // 2%
        swapProvider.setTwapSlippage(newSlippage);
        assertEq(swapProvider.twapSlippageBasisPoints(), newSlippage);
    }

    function testSetTwapSlippageRevertsForNonOwner() public {
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        swapProvider.setTwapSlippage(200);
        vm.stopPrank();
    }

    function testSetTwapSlippageRevertsForTooHighSlippage() public {
        vm.expectRevert("Slippage too high");
        swapProvider.setTwapSlippage(10001); // > 100%
    }

    function testSetTwapIntervalAsOwner() public {
        uint32 newInterval = 3600; // 1 hour
        swapProvider.setTwapInterval(newInterval);
        assertEq(uint256(swapProvider.twapInterval()), uint256(newInterval));
    }

    function testSetTwapIntervalRevertsForNonOwner() public {
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        swapProvider.setTwapInterval(3600);
        vm.stopPrank();
    }

    function testSetTwapIntervalRevertsForZeroInterval() public {
        vm.expectRevert("TWAP interval must be > 0");
        swapProvider.setTwapInterval(0);
    }

    function testSetTwapIntervalRevertsForTooLongInterval() public {
        uint32 maxInterval = swapProvider
            .twapPriceProvider()
            .MAX_TWAP_INTERVAL();
        vm.expectRevert("TWAP interval too long");
        swapProvider.setTwapInterval(maxInterval + 1);
    }

    // Helper function to deploy SwapProvider without vm.startBroadcast() for tests
    function _deploySwapProviderForTest(
        address twapPriceProvider
    ) internal returns (UniswapV3SwapProvider) {
        uint256 twapSlippageBasisPoints = 100; // 1%
        uint32 twapInterval = 1800; // 30 minutes

        UniswapV3PoolManager.Pair[]
            memory pairs = new UniswapV3PoolManager.Pair[](3);
        pairs[0] = UniswapV3PoolManager.Pair({
            tokenA: MAINNET_USDC,
            tokenB: MAINNET_WETH,
            fee: FEE_LOW
        });
        pairs[1] = UniswapV3PoolManager.Pair({
            tokenA: MAINNET_WETH,
            tokenB: MAINNET_USDT,
            fee: FEE_LOW
        });
        pairs[2] = UniswapV3PoolManager.Pair({
            tokenA: MAINNET_USDC,
            tokenB: MAINNET_USDT,
            fee: FEE_LOW
        });

        return
            new UniswapV3SwapProvider(
                ISwapRouter(SWAP_ROUTER),
                UNISWAP_V3_FACTORY,
                pairs,
                TWAPPriceProvider(twapPriceProvider),
                twapSlippageBasisPoints,
                twapInterval,
                IWETH9(MAINNET_WETH)
            );
    }
}
