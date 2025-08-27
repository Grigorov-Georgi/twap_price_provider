//SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
pragma abicoder v2;

interface IUniswapV3SwapProvider {
    struct SwapHop {
        address tokenIn;
        address tokenOut;
        uint24 fee;
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function swapExactOutputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 deadline
    ) external payable returns (uint256 amountIn);

    function swapExactInputMultihop(
        SwapHop[] calldata hops,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function swapExactOutputMultihop(
        SwapHop[] calldata hops,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint256 deadline
    ) external payable returns (uint256 amountIn);
}
