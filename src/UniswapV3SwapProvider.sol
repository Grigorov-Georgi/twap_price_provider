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

    struct SwapHop {
        address tokenIn;
        address tokenOut;
        uint24 fee;
    }

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
        require(
            address(_twapPriceProvider) != address(0),
            "Invalid TWAP provider"
        );
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
            amountOutMinimum = _twapMinOutSingleHop(
                tokenIn,
                tokenOut,
                fee,
                amountIn
            );
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
            amountInMaximum = _twapMaxInSingleHop(
                tokenIn,
                tokenOut,
                fee,
                amountOut
            );
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

    /**
     * @notice Execute a multihop exact input swap
     * @param hops Array of swap hops defining the path
     * @param amountIn The amount of input tokens to swap (ignored if first token is ETH)
     * @param amountOutMinimum The minimum amount of output tokens to receive (0 for auto TWAP calculation)
     * @param deadline The deadline for the swap
     * @return amountOut The amount of output tokens received
     */
    function swapExactInputMultihop(
        SwapHop[] calldata hops,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable returns (uint256 amountOut) {
        require(hops.length > 0, "At least 1 hop required");
        require(deadline >= block.timestamp, "Invalid deadline");

        address tokenIn = hops[0].tokenIn;
        address tokenOut = hops[hops.length - 1].tokenOut;
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

        _validateHops(hops);

        require(
            amountIn > 0 && amountIn <= type(uint128).max,
            "Invalid amount in"
        );

        // Auto-calculate minimum output using TWAP + slippage if not provided
        if (amountOutMinimum == 0) {
            amountOutMinimum = _twapMinOutMultihop(hops, amountIn);
        }
        require(amountOutMinimum > 0, "amountOutMinimum is zero");

        if (isETHIn) {
            WETH9.deposit{value: amountIn}();
        } else {
            _safeTransferFrom(tokenIn, amountIn);
        }
        _safeApprove(tokenIn, amountIn);

        bytes memory path = _buildPath(hops);

        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: path,
                recipient: isETHOut ? address(this) : msg.sender,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            });

        amountOut = swapRouter.exactInput(params);
        require(amountOut >= amountOutMinimum, "Insufficient amount out");

        if (isETHOut) {
            WETH9.withdraw(amountOut);
            (bool success, ) = msg.sender.call{value: amountOut}("");
            require(success, "ETH transfer failed");
        }

        return amountOut;
    }

    /**
     * @notice Execute a multihop exact output swap
     * @param hops Array of swap hops defining the path
     * @param amountOut The exact amount of output tokens to receive
     * @param amountInMaximum The maximum amount of input tokens to spend (ignored if first token is ETH, use msg.value)
     * @param deadline The deadline for the swap
     * @return amountIn The amount of input tokens actually spent
     */
    function swapExactOutputMultihop(
        SwapHop[] calldata hops,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 deadline
    ) external payable returns (uint256 amountIn) {
        require(hops.length > 0, "At least 1 hop required");
        require(deadline >= block.timestamp, "Invalid deadline");

        address tokenIn = hops[0].tokenIn;
        address tokenOut = hops[hops.length - 1].tokenOut;
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

        _validateHops(hops);

        require(
            amountOut > 0 && amountOut <= type(uint128).max,
            "Invalid amount out"
        );

        // Auto-calculate maximum input using TWAP + slippage if not provided
        if (amountInMaximum == 0) {
            amountInMaximum = _twapMaxInMultihop(hops, amountOut);
        }
        require(amountInMaximum > 0, "amountInMaximum is zero");

        if (isETHIn) {
            WETH9.deposit{value: amountInMaximum}();
        } else {
            _safeTransferFrom(tokenIn, amountInMaximum);
        }
        _safeApprove(tokenIn, amountInMaximum);

        bytes memory path = _buildReversedPath(hops);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter
            .ExactOutputParams({
                path: path,
                recipient: isETHOut ? address(this) : msg.sender,
                deadline: deadline,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            });

        amountIn = swapRouter.exactOutput(params);

        if (isETHIn && amountIn < amountInMaximum) {
            WETH9.withdraw(amountInMaximum - amountIn);
            (bool success, ) = msg.sender.call{
                value: amountInMaximum - amountIn
            }("");
            require(success, "ETH refund failed");
        } else if (!isETHIn && amountIn < amountInMaximum) {
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

    /// @dev Converts address(0) to WETH9 address, leaves other addresses unchanged
    function _normalizeToken(address token) internal view returns (address) {
        return token == address(0) ? address(WETH9) : token;
    }

    /// @dev Validates all hops in a multihop swap path
    function _validateHops(SwapHop[] calldata hops) internal view {
        for (uint256 i = 0; i < hops.length; i++) {
            address hopTokenIn = _normalizeToken(hops[i].tokenIn);
            address hopTokenOut = _normalizeToken(hops[i].tokenOut);
            require(hopTokenIn != hopTokenOut, "Invalid tokens");
            require(hops[i].fee > 0, "Invalid fee");
            require(
                twapPriceProvider.getPool(
                    hopTokenIn,
                    hopTokenOut,
                    hops[i].fee
                ) != address(0),
                "Invalid pool"
            );
        }
    }

    /**
     * @dev Calculates minimum output amount using TWAP price with slippage protection
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param fee Pool fee tier
     * @param amountIn Input amount
     * @return Minimum output amount accounting for slippage
     */
    function _twapMinOutSingleHop(
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
    function _twapMaxInSingleHop(
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
     * @dev Calculates minimum output amount for multihop swaps using TWAP price with slippage protection
     * @param hops Array of swap hops defining the path
     * @param amountIn Input amount
     * @return Minimum output amount accounting for slippage
     */
    function _twapMinOutMultihop(
        SwapHop[] calldata hops,
        uint256 amountIn
    ) internal view returns (uint256) {
        uint256 curTwapPrice = amountIn;

        for (uint256 i = 0; i < hops.length; i++) {
            require(curTwapPrice <= type(uint128).max, "Amount too large");

            address tokenIn = _normalizeToken(hops[i].tokenIn);
            address tokenOut = _normalizeToken(hops[i].tokenOut);

            curTwapPrice = twapPriceProvider.consult(
                tokenIn,
                tokenOut,
                hops[i].fee,
                uint128(curTwapPrice)
            );
        }

        return
            (curTwapPrice * (MAX_BASIS_POINTS - twapSlippageBasisPoints)) /
            MAX_BASIS_POINTS;
    }

    /**
     * @dev Calculates maximum input amount for multihop swaps using TWAP price with slippage protection
     * @param hops Array of swap hops defining the path
     * @param amountOut The amount of output tokens desired
     * @return Maximum input amount accounting for slippage
     */
    function _twapMaxInMultihop(
        SwapHop[] calldata hops,
        uint256 amountOut
    ) internal view returns (uint256) {
        uint256 curTwapPrice = amountOut;

        uint256 i = hops.length;
        while (i > 0) {
            i--;
            require(curTwapPrice <= type(uint128).max, "Amount too large");

            address tokenIn = _normalizeToken(hops[i].tokenIn);
            address tokenOut = _normalizeToken(hops[i].tokenOut);

            curTwapPrice = twapPriceProvider.consult(
                tokenOut,
                tokenIn,
                hops[i].fee,
                uint128(curTwapPrice)
            );
        }

        return
            (curTwapPrice * (MAX_BASIS_POINTS + twapSlippageBasisPoints)) /
            MAX_BASIS_POINTS;
    }

    /**
     * @dev Builds encoded path for exact input multihop swaps
     * @param hops Array of swap hops defining the path
     * @return path The encoded swap path for Uniswap V3
     */
    function _buildPath(
        SwapHop[] calldata hops
    ) internal view returns (bytes memory path) {
        require(hops.length > 0, "Empty hops array");

        address firstToken = _normalizeToken(hops[0].tokenIn);
        path = abi.encodePacked(firstToken);

        for (uint256 i = 0; i < hops.length; i++) {
            address tokenOut = _normalizeToken(hops[i].tokenOut);
            path = abi.encodePacked(path, hops[i].fee, tokenOut);
        }
    }

    /**
     * @dev Builds encoded reversed path for exact output multihop swaps
     * @param hops Array of swap hops defining the path
     * @return path The encoded reversed swap path for Uniswap V3
     */
    function _buildReversedPath(
        SwapHop[] calldata hops
    ) internal view returns (bytes memory path) {
        require(hops.length > 0, "Empty hops array");

        address lastToken = _normalizeToken(hops[hops.length - 1].tokenOut);
        path = abi.encodePacked(lastToken);

        uint256 i = hops.length;
        while (i > 0) {
            i--;
            address tokenIn = _normalizeToken(hops[i].tokenIn);
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
