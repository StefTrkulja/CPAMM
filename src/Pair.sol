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
    event Sync(uint256 reserveA, uint256 reserveB);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(address _tokenA, address _tokenB) {
        I_TOKEN_A = IERC20(_tokenA);
        I_TOKEN_B = IERC20(_tokenB);
    }

    function addLiquidity(
        uint256 amountA,
        uint256 amountB,
        address to
    ) external nonReentrant returns (uint256 sharesMinted) {
        require(
            amountA > 0 && amountB > 0,
            "Amounts must be greater than zero"
        );

        uint256 balanceA = I_TOKEN_A.balanceOf(address(this));
        uint256 balanceB = I_TOKEN_B.balanceOf(address(this));

        uint256 actualAmountA = balanceA - reserveA;
        uint256 actualAmountB = balanceB - reserveB;
        require(actualAmountA >= amountA && actualAmountB >= amountB);

        if (totalSupply == 0) {
            sharesMinted =
                MathLib.sqrt(actualAmountA * actualAmountB) -
                MINIMUM_LIQUIDITY;
            totalSupply += MINIMUM_LIQUIDITY;
        } else {
            uint256 shareA = (actualAmountA * totalSupply) / reserveA;
            uint256 shareB = (actualAmountB * totalSupply) / reserveB;
            sharesMinted = MathLib.min(shareA, shareB);
        }
        require(sharesMinted > 0, "Insufficient liquidity minted");
        require(to != address(0), "Invalid address");
        require(to != address(this), "Cannot mint to pair");

        mint(to, sharesMinted);

        reserveA = balanceA;
        reserveB = balanceB;

        emit Mint(to, actualAmountA, actualAmountB, sharesMinted);
        emit Sync(reserveA, reserveB);

        return sharesMinted;
    }

    function removeLiquidity(
        uint256 shares,
        address from
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(shares > 0, "Shares must be greater than zero");
        uint256 shareBalance = balances[address(this)];
        require(shareBalance >= shares, "Insufficient shares received");

        amountA = (shares * reserveA) / totalSupply;
        amountB = (shares * reserveB) / totalSupply;
        require(amountA > 0 && amountB > 0, "Insufficient amounts to withdraw");
        burn(address(this), shares);
        reserveA -= amountA;
        reserveB -= amountB;
        I_TOKEN_A.safeTransfer(from, amountA);
        I_TOKEN_B.safeTransfer(from, amountB);

        emit Burn(from, amountA, amountB, shares);
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

    function swap(
        uint256 amountIn,
        uint256 minAmountOut,
        address swappingTo,
        address to
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "AmountIn must be greater than zero");
        require(
            swappingTo == address(I_TOKEN_A) ||
                swappingTo == address(I_TOKEN_B),
            "Invalid token to swap to"
        );
        bool isSwappingToA = swappingTo == address(I_TOKEN_A);
        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            uint256 reserveIn,
            uint256 reserveOut
        ) = isSwappingToA
                ? (I_TOKEN_B, I_TOKEN_A, reserveB, reserveA)
                : (I_TOKEN_A, I_TOKEN_B, reserveA, reserveB);

        require(
            reserveIn > 0 && reserveOut > 0,
            "Insufficient liquidity in the pool"
        );

        uint256 balanceIn = tokenIn.balanceOf(address(this));
        uint256 actualAmountIn = balanceIn - reserveIn;
        require(actualAmountIn > 0, "Insufficient amount in after transfer");
        uint256 amountInWithFee = (actualAmountIn * (BASE - FEE)) / BASE;
        amountOut =
            (amountInWithFee * reserveOut) /
            (reserveIn + amountInWithFee);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        require(amountOut > 0, "AmountOut must be greater than zero");
        require(amountOut < reserveOut, "Not enough liquidity for this trade");
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

    function getReserves()
        external
        view
        returns (uint256 _reserveA, uint256 _reserveB)
    {
        _reserveA = reserveA;
        _reserveB = reserveB;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balances[from] >= amount, "Insufficient balance");
        if (from != msg.sender) {
            require(
                allowance[from][msg.sender] >= amount,
                "Insufficient allowance"
            );
            allowance[from][msg.sender] -= amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        balances[from] -= amount;
        balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function getAmountIn(
        uint256 amountOut,
        address tokenOut
    ) external view returns (uint256 amountIn) {
        require(amountOut > 0, "AmountOut must be greater than zero");
        require(
            tokenOut == address(I_TOKEN_A) || tokenOut == address(I_TOKEN_B),
            "Invalid tokenOut address"
        );

        bool isTokenOutA = tokenOut == address(I_TOKEN_A);
        (uint256 reserveIn, uint256 reserveOut) = isTokenOutA
            ? (reserveB, reserveA)
            : (reserveA, reserveB);
        require(
            reserveIn > 0 && reserveOut > 0,
            "Insufficient liquidity in the pool"
        );
        require(amountOut < reserveOut, "Insufficient liquidity");

        uint256 numerator = reserveIn * amountOut * BASE;
        uint256 denominator = (reserveOut - amountOut) * (BASE - FEE);
        amountIn = (numerator / denominator) + 1;

        return amountIn;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}
