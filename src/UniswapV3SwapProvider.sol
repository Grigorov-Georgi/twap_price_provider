// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {UniswapV3PoolManager} from "./UniswapV3PoolManager.sol";
import {ITWAPPriceProvider} from "./interfaces/ITWAPPriceProvider.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract UniswapV3SwapProvider is UniswapV3PoolManager {
    ISwapRouter public immutable swapRouter;
    ITWAPPriceProvider public immutable twapPriceProvider;
    IWETH9 public immutable WETH9;

    uint256 public twapSlippageBasisPoints = 100; // 1%
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
        require(address(_weth9) != address(0), "Invalid WETH address");

        swapRouter = _swapRouter;
        twapPriceProvider = _twapPriceProvider;
        twapSlippageBasisPoints = _twapSlippageBasisPoints;
        WETH9 = _weth9;
    }

    /**
     * @notice Swaps exact amount of input tokens for output tokens
     * @param tokenIn Address of input token (use address(0) for ETH)
     * @param tokenOut Address of output token (use address(0) for ETH)
     * @param fee Pool fee tier (500, 3000, 10000)
     * @param amountIn Exact amount of input tokens to swap (ignored if tokenIn is ETH)
     * @param amountOutMinimum Minimum output amount (0 for auto TWAP calculation)
     * @param deadline Transaction deadline timestamp
     * @return amountOut Actual amount of output tokens received
     */
    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        bool isETHIn = tokenIn == address(0);
        bool isETHOut = tokenOut == address(0);

        if (isETHIn) {
            require(msg.value > 0, "Must send ETH");
            amountIn = msg.value;
            tokenIn = address(WETH9);
        } else {
            require(msg.value == 0, "ETH not expected");
        }

        if (isETHOut) {
            tokenOut = address(WETH9);
        }

        _validateSwapParams(tokenIn, tokenOut, fee, deadline);
        require(
            amountIn > 0 && amountIn <= type(uint128).max,
            "Invalid amount in"
        );

        // Auto-calculate minimum output using TWAP + slippage if not provided
        if (amountOutMinimum == 0) {
            amountOutMinimum = _twapMinOut(tokenIn, tokenOut, fee, amountIn);
        }
        require(amountOutMinimum > 0, "amountOutMinimum is zero");

        if (isETHIn) {
            WETH9.deposit{value: amountIn}();
        } else {
            _safeTransferFrom(tokenIn, amountIn);
        }
        _safeApprove(tokenIn, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: isETHOut ? address(this) : msg.sender,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0 // we don't need price limit if we have amountOutMinimum
            });

        amountOut = swapRouter.exactInputSingle(params);
        require(amountOut >= amountOutMinimum, "Insufficient amount out");

        if (isETHOut) {
            WETH9.withdraw(amountOut);
            (bool success, ) = msg.sender.call{value: amountOut}("");
            require(success, "ETH transfer failed");
        }

        return amountOut;
    }

    /**
     * @notice Swaps input tokens for exact amount of output tokens
     * @param tokenIn Address of input token (use address(0) for ETH)
     * @param tokenOut Address of output token (use address(0) for ETH)
     * @param fee Pool fee tier (500, 3000, 10000)
     * @param amountOut Exact amount of output tokens desired
     * @param amountInMaximum Maximum input amount (ignored if tokenIn is ETH, use msg.value)
     * @param deadline Transaction deadline timestamp
     * @return amountIn Actual amount of input tokens used
     */
    function swapExactOutputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 deadline
    ) external payable returns (uint256 amountIn) {
        bool isETHIn = tokenIn == address(0);
        bool isETHOut = tokenOut == address(0);

        if (isETHIn) {
            require(msg.value > 0, "Must send ETH");
            amountInMaximum = msg.value;
            tokenIn = address(WETH9);
        } else {
            require(msg.value == 0, "ETH not expected");
        }

        if (isETHOut) {
            tokenOut = address(WETH9);
        }

        _validateSwapParams(tokenIn, tokenOut, fee, deadline);
        require(
            amountOut > 0 && amountOut <= type(uint128).max,
            "Invalid amount out"
        );

        // Auto-calculate maximum input using TWAP + slippage if not provided
        if (amountInMaximum == 0) {
            amountInMaximum = _twapMaxIn(tokenIn, tokenOut, fee, amountOut);
        }
        require(amountInMaximum > 0, "amountInMaximum is zero");

        if (isETHIn) {
            WETH9.deposit{value: amountInMaximum}();
        } else {
            _safeTransferFrom(tokenIn, amountInMaximum);
        }
        _safeApprove(tokenIn, amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: isETHOut ? address(this) : msg.sender,
                deadline: deadline,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0 // we don't need price limit if we have amountInMaximum
            });

        amountIn = swapRouter.exactOutputSingle(params);

        // Refund unused ETH or ERC20 tokens
        if (isETHIn && amountIn < amountInMaximum) {
            WETH9.withdraw(amountInMaximum - amountIn);
            (bool success, ) = msg.sender.call{
                value: amountInMaximum - amountIn
            }("");
            require(success, "ETH refund failed");
        } else if (!isETHIn && amountIn < amountInMaximum) {
            // Refund unused ERC20 tokens
            _safeTransfer(tokenIn, amountInMaximum - amountIn);
        }

        if (isETHOut) {
            WETH9.withdraw(amountOut);
            (bool success, ) = msg.sender.call{value: amountOut}("");
            require(success, "ETH transfer failed");
        }

        return amountIn;
    }

    /// @dev Safely transfers tokens from user to this contract
    function _safeTransferFrom(address tokenIn, uint256 amount) internal {
        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            amount
        );
    }

    /// @dev Safely transfers tokens from this contract to user
    function _safeTransfer(address tokenOut, uint256 amount) internal {
        TransferHelper.safeTransfer(tokenOut, msg.sender, amount);
    }

    /// @dev Safely approves tokens for swap router
    function _safeApprove(address tokenIn, uint256 amount) internal {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);
    }

    /**
     * @dev Calculates minimum output amount using TWAP price with slippage protection
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Pool fee tier
     * @param amountIn Input amount
     * @return Minimum output amount accounting for slippage
     */
    function _twapMinOut(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn
    ) internal view returns (uint256) {
        uint256 twapPrice = twapPriceProvider.consult(
            tokenIn,
            tokenOut,
            fee,
            uint128(amountIn)
        );

        // Specific order of operations is important here to avoid integer division data loss
        return
            (twapPrice * (MAX_BASIS_POINTS - twapSlippageBasisPoints)) /
            MAX_BASIS_POINTS;
    }

    /**
     * @dev Calculates maximum input amount using TWAP price with slippage protection
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Pool fee tier
     * @param amountOut Desired output amount
     * @return Maximum input amount accounting for slippage
     */
    function _twapMaxIn(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut
    ) internal view returns (uint256) {
        uint256 twapPrice = twapPriceProvider.consult(
            tokenOut,
            tokenIn,
            fee,
            uint128(amountOut)
        );

        // Specific order of operations is important here to avoid integer division data loss
        return
            (twapPrice * (MAX_BASIS_POINTS + twapSlippageBasisPoints)) /
            MAX_BASIS_POINTS;
    }

    /**
     * @dev Validates swap parameters and ensures pool exists
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Pool fee tier
     * @param deadline Transaction deadline
     */
    function _validateSwapParams(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 deadline
    ) internal view {
        require(tokenIn != tokenOut, "Invalid tokens");
        require(fee > 0, "Invalid fee");
        require(deadline >= block.timestamp, "Invalid deadline");
        require(
            twapPriceProvider.getPool(tokenIn, tokenOut, fee) != address(0),
            "Invalid pool"
        );
    }

    receive() external payable {
        require(msg.sender == address(WETH9), "Only WETH");
    }
}
