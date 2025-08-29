// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {UniswapV3PoolManager} from "./UniswapV3PoolManager.sol";
import {ITWAPPriceProvider} from "./interfaces/ITWAPPriceProvider.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {IUniswapV3SwapProvider} from "./interfaces/IUniswapV3SwapProvider.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UniswapV3SwapProvider is UniswapV3PoolManager, IUniswapV3SwapProvider, ReentrancyGuard {
    ISwapRouter public immutable swapRouter;
    ITWAPPriceProvider public immutable twapPriceProvider;
    IWETH9 public immutable WETH9;

    uint256 public immutable twapSlippageBasisPoints;
    uint256 private constant MAX_BASIS_POINTS = 10000; // 100%

    /**
     * @notice Initializes the UniswapV3SwapProvider contract
     * @param _swapRouter Uniswap V3 SwapRouter contract address
     * @param _factory Uniswap V3 Factory contract address
     * @param pairs Array of token pairs to enable for swapping
     * @param _twapPriceProvider TWAP price provider for slippage protection
     * @param _twapSlippageBasisPoints Default slippage tolerance in basis points (100 = 1%)
     * @param _weth9 WETH9 contract address for ETH/WETH conversions
     */
    constructor(
        ISwapRouter _swapRouter,
        address _factory,
        Pair[] memory pairs,
        ITWAPPriceProvider _twapPriceProvider,
        uint256 _twapSlippageBasisPoints,
        IWETH9 _weth9
    ) UniswapV3PoolManager(_factory, pairs) {
        require(address(_swapRouter) != address(0), "Invalid swap router");
        require(address(_twapPriceProvider) != address(0), "Invalid TWAP provider");
        require(address(_weth9) != address(0), "Invalid WETH address");

        swapRouter = _swapRouter;
        twapPriceProvider = _twapPriceProvider;
        twapSlippageBasisPoints = _twapSlippageBasisPoints;
        WETH9 = _weth9;
    }

    /**
     * @notice Execute a multihop exact input swap with ERC20 tokens
     * @param hops Array of swap hops defining the path
     * @param amountIn The amount of input tokens to swap
     * @param amountOutMinimum The minimum amount of output tokens to receive (0 for auto TWAP calculation)
     * @param deadline The deadline for the swap
     * @return amountOut The amount of output tokens received
     */
    function swapExactInput(SwapHop[] calldata hops, uint256 amountIn, uint256 amountOutMinimum, uint256 deadline)
        external
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        require(hops.length > 0, "At least 1 hop required");
        require(deadline >= block.timestamp, "Invalid deadline");
        require(amountIn > 0 && amountIn <= type(uint128).max, "Invalid amount in");

        address tokenIn = hops[0].tokenIn;

        _validateHops(hops);

        if (amountOutMinimum == 0) {
            amountOutMinimum = _twapMinOutMultihop(hops, amountIn);
        }
        require(amountOutMinimum > 0, "amountOutMinimum is zero");

        _safeTransferFrom(tokenIn, amountIn);
        _safeApprove(tokenIn, amountIn);

        bytes memory path = _buildPath(hops);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = swapRouter.exactInput(params);
        return amountOut;
    }

    /**
     * @notice Execute a multihop exact input swap from native ETH to ERC20 token
     * @param hops Array of swap hops defining the path (first token should be address(0) for ETH, last token must be ERC20)
     * @param amountOutMinimum The minimum amount of output tokens to receive (0 for auto TWAP calculation)
     * @param deadline The deadline for the swap
     * @return amountOut The amount of output tokens received
     */
    function swapExactInputNative(SwapHop[] calldata hops, uint256 amountOutMinimum, uint256 deadline)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        require(hops.length > 0, "At least 1 hop required");
        require(deadline >= block.timestamp, "Invalid deadline");
        require(msg.value > 0, "Must send ETH");
        require(msg.value <= type(uint128).max, "Invalid amount in");
        require(hops[0].tokenIn == address(0), "First token must be ETH");
        uint256 amountIn = msg.value;
        address tokenOut = hops[hops.length - 1].tokenOut;
        require(tokenOut != address(0), "Output token must be ERC20");

        _validateHops(hops);

        if (amountOutMinimum == 0) {
            amountOutMinimum = _twapMinOutMultihop(hops, amountIn);
        }
        require(amountOutMinimum > 0, "amountOutMinimum is zero");

        WETH9.deposit{value: amountIn}();
        _safeApprove(address(WETH9), amountIn);

        bytes memory path = _buildPath(hops);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = swapRouter.exactInput(params);

        return amountOut;
    }

    /**
     * @notice Execute a multihop exact output swap with ERC20 tokens
     * @param hops Array of swap hops defining the path
     * @param amountOut The exact amount of output tokens to receive
     * @param amountInMaximum The maximum amount of input tokens to spend (0 for auto TWAP calculation)
     * @param deadline The deadline for the swap
     * @return amountIn The amount of input tokens actually spent
     */
    function swapExactOutput(SwapHop[] calldata hops, uint256 amountOut, uint256 amountInMaximum, uint256 deadline)
        external
        override
        nonReentrant
        returns (uint256 amountIn)
    {
        require(hops.length > 0, "At least 1 hop required");
        require(deadline >= block.timestamp, "Invalid deadline");
        require(amountOut > 0 && amountOut <= type(uint128).max, "Invalid amount out");

        address tokenIn = hops[0].tokenIn;

        _validateHops(hops);

        if (amountInMaximum == 0) {
            amountInMaximum = _twapMaxInMultihop(hops, amountOut);
        }
        require(amountInMaximum > 0, "amountInMaximum is zero");

        _safeTransferFrom(tokenIn, amountInMaximum);
        _safeApprove(tokenIn, amountInMaximum);

        bytes memory path = _buildReversedPath(hops);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: msg.sender,
            deadline: deadline,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum
        });

        amountIn = swapRouter.exactOutput(params);

        if (amountIn < amountInMaximum) {
            _safeTransfer(tokenIn, amountInMaximum - amountIn);
        }

        return amountIn;
    }

    /**
     * @notice Execute a multihop exact output swap from native ETH to ERC20 token
     * @param hops Array of swap hops defining the path (first token should be address(0) for ETH, last token must be ERC20)
     * @param amountOut The exact amount of output tokens to receive
     * @param deadline The deadline for the swap
     * @return amountIn The amount of ETH actually spent
     */
    function swapExactOutputNative(SwapHop[] calldata hops, uint256 amountOut, uint256 deadline)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountIn)
    {
        require(hops.length > 0, "At least 1 hop required");
        require(deadline >= block.timestamp, "Invalid deadline");
        require(msg.value > 0, "Must send ETH");
        require(amountOut > 0 && amountOut <= type(uint128).max, "Invalid amount out");
        require(hops[0].tokenIn == address(0), "First token must be ETH");

        uint256 amountInMaximum = msg.value;
        address tokenOut = hops[hops.length - 1].tokenOut;
        require(tokenOut != address(0), "Output token must be ERC20");

        _validateHops(hops);

        WETH9.deposit{value: amountInMaximum}();
        _safeApprove(address(WETH9), amountInMaximum);

        bytes memory path = _buildReversedPath(hops);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: msg.sender,
            deadline: deadline,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum
        });

        amountIn = swapRouter.exactOutput(params);

        if (amountIn < amountInMaximum) {
            WETH9.withdraw(amountInMaximum - amountIn);
            (bool success,) = msg.sender.call{value: amountInMaximum - amountIn}("");
            require(success, "ETH refund failed");
        }

        return amountIn;
    }

    /// @dev Safely transfers tokens from user to this contract
    function _safeTransferFrom(address tokenIn, uint256 amount) internal {
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amount);
    }

    /// @dev Safely transfers tokens from this contract to user
    function _safeTransfer(address tokenOut, uint256 amount) internal {
        TransferHelper.safeTransfer(tokenOut, msg.sender, amount);
    }

    /// @dev Safely approves tokens for swap router
    function _safeApprove(address tokenIn, uint256 amount) internal {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
        if (amount > 0) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);
        }
    }

    /// @dev Validates all hops in a multihop swap path
    function _validateHops(SwapHop[] calldata hops) internal view {
        for (uint256 i = 0; i < hops.length; i++) {
            address tokenIn = (i == 0 && hops[i].tokenIn == address(0)) ? address(WETH9) : hops[i].tokenIn;

            require(tokenIn != hops[i].tokenOut, "Invalid tokens");
            require(hops[i].fee > 0, "Invalid fee");
            require(twapPriceProvider.getPool(tokenIn, hops[i].tokenOut, hops[i].fee) != address(0), "Invalid pool");
        }
    }

    /**
     * @dev Calculates minimum output amount for multihop swaps using TWAP price with slippage protection
     * @param hops Array of swap hops defining the path
     * @param amountIn Input amount
     * @return Minimum output amount accounting for slippage
     */
    function _twapMinOutMultihop(SwapHop[] calldata hops, uint256 amountIn) internal view returns (uint256) {
        uint256 curTwapPrice = amountIn;

        for (uint256 i = 0; i < hops.length; i++) {
            require(curTwapPrice <= type(uint128).max, "Amount too large");

            address tokenIn = (i == 0 && hops[i].tokenIn == address(0)) ? address(WETH9) : hops[i].tokenIn;
            address tokenOut = hops[i].tokenOut;

            curTwapPrice = twapPriceProvider.consult(tokenIn, tokenOut, hops[i].fee, uint128(curTwapPrice));
        }

        return (curTwapPrice * (MAX_BASIS_POINTS - twapSlippageBasisPoints)) / MAX_BASIS_POINTS;
    }

    /**
     * @dev Calculates maximum input amount for multihop swaps using TWAP price with slippage protection
     * @param hops Array of swap hops defining the path
     * @param amountOut The amount of output tokens desired
     * @return Maximum input amount accounting for slippage
     */
    function _twapMaxInMultihop(SwapHop[] calldata hops, uint256 amountOut) internal view returns (uint256) {
        uint256 curTwapPrice = amountOut;

        uint256 i = hops.length;
        while (i > 0) {
            i--;
            require(curTwapPrice <= type(uint128).max, "Amount too large");

            address tokenIn = (i == 0 && hops[i].tokenIn == address(0)) ? address(WETH9) : hops[i].tokenIn;
            address tokenOut = hops[i].tokenOut;

            curTwapPrice = twapPriceProvider.consult(tokenOut, tokenIn, hops[i].fee, uint128(curTwapPrice));
        }

        return (curTwapPrice * (MAX_BASIS_POINTS + twapSlippageBasisPoints)) / MAX_BASIS_POINTS;
    }

    /**
     * @dev Builds encoded path for exact input multihop swaps
     * @param hops Array of swap hops defining the path
     * @return path The encoded swap path for Uniswap V3
     */
    function _buildPath(SwapHop[] calldata hops) internal view returns (bytes memory path) {
        require(hops.length > 0, "Empty hops array");

        address firstToken = hops[0].tokenIn == address(0) ? address(WETH9) : hops[0].tokenIn;
        path = abi.encodePacked(firstToken);

        for (uint256 i = 0; i < hops.length; i++) {
            path = abi.encodePacked(path, hops[i].fee, hops[i].tokenOut);
        }
    }

    /**
     * @dev Builds encoded reversed path for exact output multihop swaps
     * @param hops Array of swap hops defining the path
     * @return path The encoded reversed swap path for Uniswap V3
     */
    function _buildReversedPath(SwapHop[] calldata hops) internal view returns (bytes memory path) {
        require(hops.length > 0, "Empty hops array");

        path = abi.encodePacked(hops[hops.length - 1].tokenOut);

        uint256 i = hops.length;
        while (i > 0) {
            i--;
            address tokenIn = (i == 0 && hops[i].tokenIn == address(0)) ? address(WETH9) : hops[i].tokenIn;
            path = abi.encodePacked(path, hops[i].fee, tokenIn);
        }
    }

    /**
     * @dev Validates swap parameters and ensures pool exists
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Pool fee tier
     * @param deadline Transaction deadline
     */
    function _validateSwapParams(address tokenIn, address tokenOut, uint24 fee, uint256 deadline) internal view {
        require(tokenIn != tokenOut, "Invalid tokens");
        require(fee > 0, "Invalid fee");
        require(deadline >= block.timestamp, "Invalid deadline");
        require(twapPriceProvider.getPool(tokenIn, tokenOut, fee) != address(0), "Invalid pool");
    }

    receive() external payable {
        require(msg.sender == address(WETH9), "Only WETH");
    }
}
