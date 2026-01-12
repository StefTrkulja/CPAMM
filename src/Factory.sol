// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Pair} from "./Pair.sol";

contract Factory {
    address[] public allPairs;
    mapping(address => mapping(address => address)) public getPair;

    error Factory__IdenticalAddresses();
    error Factory__ZeroAddress();
    error Factory__PairExists();

    event PairCreated(
        address indexed tokenA,
        address indexed tokenB,
        address pair,
        uint256
    );

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair) {
        if (tokenA == tokenB) revert Factory__IdenticalAddresses();
        if (tokenA == address(0) || tokenB == address(0)) {
            revert Factory__ZeroAddress();
        }
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        if (getPair[token0][token1] != address(0)) revert Factory__PairExists();
        pair = address(new Pair(token0, token1));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
