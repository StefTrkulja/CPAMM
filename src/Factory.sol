// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Pair} from "./Pair.sol";

contract Factory {
    address[] public allPairs;
    mapping(address => mapping(address => address)) public getPair;
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
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        require(
            tokenA != address(0) && tokenB != address(0),
            "Factory: ZERO_ADDRESS"
        );
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(getPair[token0][token1] == address(0), "Factory: PAIR_EXISTS");
        pair = address(new Pair(token0, token1));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
