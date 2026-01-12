// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Factory} from "./Factory.sol";
import {Pair} from "./Pair.sol";

contract Router {
    using SafeERC20 for IERC20;
    Factory public immutable FACTORY;

    error Router__Expired();
    error Router__InvalidToAddress();
    error Router__PairNotExist();
    error Router__InsufficientShares();
    error Router__InsufficientAllowance();
    error Router__TransferFailed();
    error Router__InsufficientAAmount();
    error Router__InsufficientBAmount();
    error Router__InsufficientInputAmount();
    error Router__InsufficientOutputAmount();
    error Router__ExcessiveInputAmount();

    constructor(address factoryAddress) {
        FACTORY = Factory(factoryAddress);
    }

    modifier ensure(uint256 deadline) {
        _ensure(deadline);
        _;
    }

    function _ensure(uint256 deadline) internal view {
        if (deadline < block.timestamp) revert Router__Expired();
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
        if (to == address(0)) revert Router__InvalidToAddress();

        address pairAddress = FACTORY.getPair(tokenA, tokenB);
        if (pairAddress == address(0)) revert Router__PairNotExist();

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
        if (to == address(0)) revert Router__InvalidToAddress();

        address pairAddress = FACTORY.getPair(tokenA, tokenB);
        if (pairAddress == address(0)) revert Router__PairNotExist();

        if (shares == 0) revert Router__InsufficientShares();
        if (Pair(pairAddress).allowance(msg.sender, address(this)) < shares) {
            revert Router__InsufficientAllowance();
        }
        if (!Pair(pairAddress).transferFrom(msg.sender, pairAddress, shares)) {
            revert Router__TransferFailed();
        }

        (uint256 amount0, uint256 amount1) = Pair(pairAddress).removeLiquidity(
            shares,
            to
        );
        (amountA, amountB) = tokenA < tokenB
            ? (amount0, amount1)
            : (amount1, amount0);

        if (amountA < amountAMin) revert Router__InsufficientAAmount();
        if (amountB < amountBMin) revert Router__InsufficientBAmount();

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
                if (amount1Optimal < amountBMinSorted) {
                    revert Router__InsufficientBAmount();
                }
                amount0 = amountADesiredSorted;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amountBDesiredSorted * reserve0) /
                    reserve1;
                if (amount0Optimal > amountADesiredSorted) {
                    revert Router__InsufficientAAmount();
                }
                if (amount0Optimal < amountAMinSorted) {
                    revert Router__InsufficientAAmount();
                }
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
        if (to == address(0)) revert Router__InvalidToAddress();
        if (amountIn == 0) revert Router__InsufficientInputAmount();
        address pairAddress = FACTORY.getPair(tokenIn, tokenOut);
        if (pairAddress == address(0)) revert Router__PairNotExist();

        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddress, amountIn);

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
        if (to == address(0)) revert Router__InvalidToAddress();
        if (amountOut == 0) revert Router__InsufficientOutputAmount();
        address pairAddress = FACTORY.getPair(tokenIn, tokenOut);
        if (pairAddress == address(0)) revert Router__PairNotExist();

        amountIn = Pair(pairAddress).getAmountIn(amountOut, tokenOut);
        if (amountIn > amountInMax) revert Router__ExcessiveInputAmount();

        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddress, amountIn);

        uint256 actualAmountOut = Pair(pairAddress).swap(
            amountIn,
            amountOut,
            tokenOut,
            to
        );
        if (actualAmountOut < amountOut) revert Router__InsufficientOutputAmount();

        return amountIn;
    }
}
