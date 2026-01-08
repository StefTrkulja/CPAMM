// SPDX License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Factory} from "./Factory.sol";
import {Pair} from "./Pair.sol";    

contract Router {
    using SafeERC20 for IERC20;
    Factory public immutable factory;
    
    constructor(address factoryAddress) {
        factory = Factory(factoryAddress);
    }

    modifier ensure(uint256 deadline){
        require(deadline >= block.timestamp, "Router: EXPIRED");
        _;
    }

    function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired,uint256 amountAMin,uint256 amountBMin, address to, uint256 deadline) public ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 shares) {
        require(to != address(0), "Router: INVALID_TO_ADDRESS");

        address pairAddress = factory.getPair(tokenA, tokenB);
        require(pairAddress != address(0), "Router: PAIR_NOT_EXIST");

        (amountA, amountB) = calculateLiquidityAmounts(pairAddress, tokenA, tokenB, amountADesired, amountBDesired, amountAMin,  amountBMin);

        IERC20(tokenA).safeTransferFrom(msg.sender, pairAddress, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pairAddress, amountB);

        IERC20(tokenA).forceApprove(pairAddress, amountA);
        IERC20(tokenB).forceApprove(pairAddress, amountB);

        shares = Pair(pairAddress).addLiquidity(amountA, amountB, to);

        return (amountA, amountB, shares);        
    }
    function removeLiquidity(address tokenA, address tokenB, uint256 shares, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        require(to != address(0), "Router: INVALID_TO_ADDRESS");

        address pairAddress = factory.getPair(tokenA, tokenB);
        require(pairAddress != address(0), "Router: PAIR_NOT_EXIST");

        require(Pair(pairAddress).transferFrom(msg.sender, address(this), shares), "Router: TRANSFER_FAILED");
        
        (uint256 amount0, uint256 amount1) = Pair(pairAddress).removeLiquidity(shares);
        (amountA, amountB) = tokenA < tokenB ? (amount0, amount1) : (amount1, amount0);

        require(amountA >= amountAMin, "Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "Router: INSUFFICIENT_B_AMOUNT");

        IERC20(tokenA).safeTransfer(to, amountA);
        IERC20(tokenB).safeTransfer(to, amountB);

        return (amountA, amountB);
    }



    function calculateLiquidityAmounts(address pairAddress, address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin) internal view returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = Pair(pairAddress).getReserves();
        (uint256 amountADesiredSorted, uint256 amountBDesiredSorted) = tokenA < tokenB ? (amountADesired, amountBDesired) : (amountBDesired, amountADesired);
        (uint256 amountAMinSorted, uint256 amountBMinSorted) = tokenA < tokenB ? (amountAMin, amountBMin) : (amountBMin, amountAMin);
        if(reserveA == 0 && reserveB == 0){
            amountA = amountADesiredSorted;
            amountB = amountBDesiredSorted;
        } else {
            uint256 amountBOptimal = (amountADesiredSorted * reserveB) / reserveA;
            if(amountBOptimal <= amountBDesiredSorted){
                require(amountBOptimal >= amountBMinSorted, "Router: INSUFFICIENT_B_AMOUNT");
                amountA = amountADesiredSorted;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountBDesiredSorted * reserveA) / reserveB;
                require(amountAOptimal <= amountADesiredSorted, "Router: INSUFFICIENT_A_AMOUNT");
                require(amountAOptimal >= amountAMinSorted, "Router: INSUFFICIENT_A_AMOUNT");
                amountA = amountAOptimal;
                amountB = amountBDesiredSorted;
            }
        }

        return (amountA, amountB);
    }
}