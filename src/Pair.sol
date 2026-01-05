// SPDX License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {MathLib} from "../lib/MathLib.sol";
contract Pair is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Konstante za fee, base i minimum liquidity. Ne mogu zakucati 0.97 jer solidity ne podrzava decimalne brojeve
    uint256 public constant FEE = 30;
    uint256 public constant BASE = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    //Dodati tokenA i tokenB kao immutable varijable jer se postavljaju samo jednom u konstruktoru
    IERC20 public immutable i_tokenA;
    uint256 public reserveA;

    IERC20 public immutable i_tokenB;
    uint256 public reserveB;

    uint256 public totalSupply;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(address _tokenA, address _tokenB) {
        i_tokenA = IERC20(_tokenA);
        i_tokenB = IERC20(_tokenB);
    }

    function addLiquidity (uint256 amountA, uint256 amountB, address to) external nonReentrant returns (uint256 sharesMinted) {
        //Proverava da su uneti iznosi veci od nule
        require(amountA > 0 && amountB > 0, "Amounts must be greater than zero");
        //Transferuje tokenA i tokenB iz korisnikovog walleta na ovaj ugovor
        i_tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        i_tokenB.safeTransferFrom(msg.sender, address(this), amountB);
        //Racunanje broja share-ova koje treba mintovati
        if (totalSupply == 0) {
            sharesMinted = MathLib.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            totalSupply += MINIMUM_LIQUIDITY; // Zakljucavamo MINIMUM_LIQUIDITY
        } else {
            uint256 shareA = (amountA * totalSupply) / reserveA;
            uint256 shareB = (amountB * totalSupply) / reserveB;
            sharesMinted = MathLib.min(shareA, shareB);
        }
        require(sharesMinted > 0, "Insufficient liquidity minted");
        require(to != address(0), "Invalid address");
        //Mintovanje share-ova korisniku
        //mint();
        
        //Updateovanje rezerva
        reserveA = i_tokenA.balanceOf(address(this));
        reserveB = i_tokenB.balanceOf(address(this));
        //nemoj zab da dodas evente

    }



    function removeLiquidity () external {}
    function mint() external {}
    function burn() external {} 
    function swap() external {}


}
