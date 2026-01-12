// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Factory} from "./Factory.sol";
import {Pair} from "./Pair.sol";

contract Router {
    using SafeERC20 for IERC20;
    Factory public immutable FACTORY;

    constructor(address factoryAddress) {
        FACTORY = Factory(factoryAddress);
    }

    modifier ensure(uint256 deadline) {
        _ensure(deadline);
        _;
    }

    function _ensure(uint256 deadline) internal view {
        require(deadline >= block.timestamp, "Router: EXPIRED");
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 shares)
    {
        require(to != address(0), "Router: INVALID_TO_ADDRESS");

        address pairAddress = FACTORY.getPair(tokenA, tokenB);
        require(pairAddress != address(0), "Router: PAIR_NOT_EXIST");

        (amountA, amountB) = calculateLiquidityAmounts(
            pairAddress,
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        IERC20(tokenA).safeTransferFrom(msg.sender, pairAddress, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pairAddress, amountB);

        (uint256 amount0, uint256 amount1) = tokenA < tokenB
            ? (amountA, amountB)
            : (amountB, amountA);
        shares = Pair(pairAddress).addLiquidity(amount0, amount1, to);

        return (amountA, amountB, shares);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 shares,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        require(to != address(0), "Router: INVALID_TO_ADDRESS");

        address pairAddress = FACTORY.getPair(tokenA, tokenB);
        require(pairAddress != address(0), "Router: PAIR_NOT_EXIST");

        require(shares > 0, "Router: INSUFFICIENT_SHARES");
        require(
            Pair(pairAddress).allowance(msg.sender, address(this)) >= shares,
            "Router: INSUFFICIENT_ALLOWANCE"
        );
        require(
            Pair(pairAddress).transferFrom(msg.sender, pairAddress, shares),
            "Router: TRANSFER_FAILED"
        );

        (uint256 amount0, uint256 amount1) = Pair(pairAddress).removeLiquidity(
            shares,
            to
        );
        (amountA, amountB) = tokenA < tokenB
            ? (amount0, amount1)
            : (amount1, amount0);

        require(amountA >= amountAMin, "Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "Router: INSUFFICIENT_B_AMOUNT");

        return (amountA, amountB);
    }

    function calculateLiquidityAmounts(
        address pairAddress,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        (uint256 reserve0, uint256 reserve1) = Pair(pairAddress).getReserves();

        (uint256 amountADesiredSorted, uint256 amountBDesiredSorted) = tokenA <
            tokenB
            ? (amountADesired, amountBDesired)
            : (amountBDesired, amountADesired);
        (uint256 amountAMinSorted, uint256 amountBMinSorted) = tokenA < tokenB
            ? (amountAMin, amountBMin)
            : (amountBMin, amountAMin);

        uint256 amount0;
        uint256 amount1;

        if (reserve0 == 0 && reserve1 == 0) {
            amount0 = amountADesiredSorted;
            amount1 = amountBDesiredSorted;
        } else {
            uint256 amount1Optimal = (amountADesiredSorted * reserve1) /
                reserve0;
            if (amount1Optimal <= amountBDesiredSorted) {
                require(
                    amount1Optimal >= amountBMinSorted,
                    "Router: INSUFFICIENT_B_AMOUNT"
                );
                amount0 = amountADesiredSorted;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amountBDesiredSorted * reserve0) /
                    reserve1;
                require(
                    amount0Optimal <= amountADesiredSorted,
                    "Router: INSUFFICIENT_A_AMOUNT"
                );
                require(
                    amount0Optimal >= amountAMinSorted,
                    "Router: INSUFFICIENT_A_AMOUNT"
                );
                amount0 = amount0Optimal;
                amount1 = amountBDesiredSorted;
            }
        }

        (amountA, amountB) = tokenA < tokenB
            ? (amount0, amount1)
            : (amount1, amount0);
        return (amountA, amountB);
    }

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountOut) {
        require(to != address(0), "Router: INVALID_TO_ADDRESS");
        require(amountIn > 0, "Router: INSUFFICIENT_INPUT_AMOUNT");
        address pairAddress = FACTORY.getPair(tokenIn, tokenOut);
        require(pairAddress != address(0), "Router: PAIR_NOT_EXIST");

        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddress, amountIn);

        // Pass amountIn for verification that correct amount was transferred
        amountOut = Pair(pairAddress).swap(
            amountIn,
            amountOutMin,
            tokenOut,
            to
        );
        return amountOut;
    }

    function swapTokensToExactTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountIn) {
        require(to != address(0), "Router: INVALID_TO_ADDRESS");
        require(amountOut > 0, "Router: INSUFFICIENT_OUTPUT_AMOUNT");
        address pairAddress = FACTORY.getPair(tokenIn, tokenOut);
        require(pairAddress != address(0), "Router: PAIR_NOT_EXIST");

        amountIn = Pair(pairAddress).getAmountIn(amountOut, tokenOut);
        require(amountIn <= amountInMax, "Router: EXCESSIVE_INPUT_AMOUNT");

        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddress, amountIn);

        uint256 actualAmountOut = Pair(pairAddress).swap(
            amountIn,
            amountOut,
            tokenOut,
            to
        );
        require(
            actualAmountOut >= amountOut,
            "Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        return amountIn;
    }
}
