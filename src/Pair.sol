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
    uint256 public constant MINIMUM_LIQUIDITY = 1000000;

    //Dodati tokenA i tokenB kao immutable varijable jer se postavljaju samo jednom u konstruktoru
    IERC20 public immutable I_TOKEN_A;
    uint256 public reserveA;

    IERC20 public immutable I_TOKEN_B;
    uint256 public reserveB;

    uint256 public totalSupply;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;

    event Swap(
        address indexed sender,
        address indexed to,
        address indexed swappingTo,
        uint256 amountIn,
        uint256 amountOut
    );
    event Mint(
        address indexed to,
        uint256 amountA,
        uint256 amountB,
        uint256 sharesMinted
    );
    event Burn(
        address indexed from,
        uint256 amountA,
        uint256 amountB,
        uint256 sharesBurned
    );
    event Sync(
        uint256 reserveA,
        uint256 reserveB
    );
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(address _tokenA, address _tokenB) {
        I_TOKEN_A = IERC20(_tokenA);
        I_TOKEN_B = IERC20(_tokenB);
    }

    function addLiquidity (uint256 amountA, uint256 amountB, address to) external nonReentrant returns (uint256 sharesMinted) {
        //Proverava da su uneti iznosi veci od nule
        require(amountA > 0 && amountB > 0, "Amounts must be greater than zero");
        //Transferuje tokenA i tokenB iz korisnikovog walleta na ovaj ugovor
        I_TOKEN_A.safeTransferFrom(msg.sender, address(this), amountA);
        I_TOKEN_B.safeTransferFrom(msg.sender, address(this), amountB);
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
        reserveA = I_TOKEN_A.balanceOf(address(this));
        reserveB = I_TOKEN_B.balanceOf(address(this));
        //nemoj zab da dodas evente
        emit Mint(to, amountA, amountB, sharesMinted);
        emit Sync(reserveA, reserveB);

        return sharesMinted;

    }

    function removeLiquidity (uint256 shares) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require (shares > 0, "Shares must be greater than zero");
        require (shares <= balances[msg.sender], "Insufficient shares to burn");
        //racunam koliko tokenA i tokenB korisnik treba da dobije
        amountA = (shares * reserveA) / totalSupply;
        amountB = (shares * reserveB) / totalSupply;
        require(amountA > 0 && amountB > 0, "Insufficient amounts to withdraw");
        //burnovanje share-ova, koristio sam CEI pattern, pa prvo burnujem pa onda saljem tokene(dodatni security)
        burn(msg.sender, shares);
        reserveA -= amountA;
        reserveB -= amountB;
        //transfer tokenA i tokenB korisniku
        I_TOKEN_A.safeTransfer(msg.sender, amountA);
        I_TOKEN_B.safeTransfer(msg.sender, amountB);

        emit Burn(msg.sender, amountA, amountB, shares);
        emit Sync(reserveA, reserveB);
        return (amountA, amountB);
    }
    function mint(address to, uint256 shares) private {
        balances[to] += shares;
        totalSupply += shares;
        emit Transfer(address(0), to, shares);
    }
    function burn(address from, uint256 shares) private {
        require(balances[from] >= shares, "Insufficient balance to burn");
        balances[from] -= shares;
        totalSupply -= shares;
        emit Transfer(from, address(0), shares);
    }
    /*Prvo cu proveriti da li je amountin validna, i da li je swapping to Token A ili Token B
      Onda cu cu pogledati rezerve i izracunati koliko korisnik treba da dobije tokena nakon swapa
        Koristicu formulu sa fee-jem: amountOut = (amountIn * (BASE - FEE) * reserveOut) / (reserveIn * BASE + amountIn * (BASE - FEE))
        Provericu da li je izracunati amountOut veci ili jednak od minAmountOut
        Azuriracu rezerve nakon swapa
     */ 
    function swap(uint256 amountIn, uint256 minAmountOut, address swappingTo, address to) external nonReentrant returns (uint256 amountOut) {
        require (amountIn > 0, "AmountIn must be greater than zero");
        require (swappingTo == address(I_TOKEN_A) || swappingTo == address(I_TOKEN_B), "Invalid token to swap to");
        bool isSwappingToA = swappingTo == address(I_TOKEN_A);
        //Prvo bitno sam napisao sa IFom, ali sam onda video da moze lepse sa ternary operatorom, a i more gas efficient je.
        (IERC20 tokenIn, IERC20 tokenOut, uint256 reserveIn, uint256 reserveOut) = isSwappingToA ? (I_TOKEN_B, I_TOKEN_A, reserveB, reserveA) : (I_TOKEN_A, I_TOKEN_B, reserveA, reserveB);
        //Transferujem tokenIn od korisnika
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity in the pool");
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 balanceIn = tokenIn.balanceOf(address(this));
        // Racunam stvarni amountIn koji je dosao na ugovor u slucaju da je token sa fee-jem pri transferu
        // Postoje ERC20 tokeni koji uzimaju fee prilikom transfera, pa je bitno da izracunam stvarni amountIn
        uint256 actualAmountIn = balanceIn - reserveIn;
        require(actualAmountIn > 0, "Insufficient amount in after transfer");
        // Racunam amountIn sa fee-jem
        uint256 amountInWithFee = (actualAmountIn * (BASE - FEE)) / BASE;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        require(amountOut > 0, "AmountOut must be greater than zero");
        require(amountOut < reserveOut, "Not enough liquidity for this trade");
        // prvo updateujem rezerve pa onda saljem tokene, CEI pattern
        if (isSwappingToA) {
            reserveA -= amountOut;
            reserveB += actualAmountIn;
        } else {
            reserveB -= amountOut;
            reserveA += actualAmountIn;
        }
        tokenOut.safeTransfer(to, amountOut);
        emit Swap(msg.sender, to, swappingTo, actualAmountIn, amountOut);
        emit Sync(reserveA, reserveB);

        return amountOut;
    }


}
