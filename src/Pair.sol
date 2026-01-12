// SPDX-License-Identifier: MIT
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

    error Pair__AmountsMustBeGreaterThanZero();
    error Pair__InsufficientTokensTransferred();
    error Pair__NoTokensReceived();
    error Pair__InsufficientLiquidityMinted();
    error Pair__InvalidAddress();
    error Pair__CannotMintToPair();
    error Pair__SharesMustBeGreaterThanZero();
    error Pair__InsufficientSharesReceived();
    error Pair__InsufficientAmountsToWithdraw();
    error Pair__InsufficientReserves();
    error Pair__InsufficientBalanceToBurn();
    error Pair__AmountInMustBeGreaterThanZero();
    error Pair__InvalidTokenToSwapTo();
    error Pair__InsufficientLiquidityInPool();
    error Pair__InsufficientAmountInAfterTransfer();
    error Pair__AmountInMismatch();
    error Pair__InsufficientOutputAmount();
    error Pair__AmountOutMustBeGreaterThanZero();
    error Pair__NotEnoughLiquidityForTrade();
    error Pair__KInvariantViolation();
    error Pair__TransferToZeroAddress();
    error Pair__InsufficientBalance();
    error Pair__InsufficientAllowance();
    error Pair__InvalidTokenOutAddress();
    error Pair__InsufficientLiquidity();
    constructor(address _tokenA, address _tokenB) {
        I_TOKEN_A = IERC20(_tokenA);
        I_TOKEN_B = IERC20(_tokenB);
    }

    function addLiquidity(
        uint256 amountA,
        uint256 amountB,
        address to
    ) external nonReentrant returns (uint256 sharesMinted) {
        if (amountA == 0 || amountB == 0) revert Pair__AmountsMustBeGreaterThanZero();

        uint256 balanceA = I_TOKEN_A.balanceOf(address(this));
        uint256 balanceB = I_TOKEN_B.balanceOf(address(this));

        uint256 actualAmountA = balanceA - reserveA;
        uint256 actualAmountB = balanceB - reserveB;
        if (actualAmountA < amountA || actualAmountB < amountB) {
            revert Pair__InsufficientTokensTransferred();
        }
        if (actualAmountA == 0 || actualAmountB == 0) revert Pair__NoTokensReceived();

        if (totalSupply == 0) {
            sharesMinted = MathLib.sqrt(actualAmountA * actualAmountB);
            if (sharesMinted <= MINIMUM_LIQUIDITY) {
                revert Pair__InsufficientLiquidityMinted();
            }
            mint(address(0), MINIMUM_LIQUIDITY);
            sharesMinted -= MINIMUM_LIQUIDITY;
        } else {
            uint256 shareA = (actualAmountA * totalSupply) / reserveA;
            uint256 shareB = (actualAmountB * totalSupply) / reserveB;
            sharesMinted = MathLib.min(shareA, shareB);
        }
        if (sharesMinted == 0) revert Pair__InsufficientLiquidityMinted();
        if (to == address(0)) revert Pair__InvalidAddress();
        if (to == address(this)) revert Pair__CannotMintToPair();

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
        if (shares == 0) revert Pair__SharesMustBeGreaterThanZero();
        uint256 shareBalance = balances[address(this)];
        if (shareBalance < shares) revert Pair__InsufficientSharesReceived();

        amountA = (shares * reserveA) / totalSupply;
        amountB = (shares * reserveB) / totalSupply;
        if (amountA == 0 || amountB == 0)
            revert Pair__InsufficientAmountsToWithdraw();
        if (amountA > reserveA || amountB > reserveB) {
            revert Pair__InsufficientReserves();
        }
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
        if (balances[from] < shares) revert Pair__InsufficientBalanceToBurn();
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
        if (amountIn == 0) revert Pair__AmountInMustBeGreaterThanZero();
        if (
            swappingTo != address(I_TOKEN_A) && swappingTo != address(I_TOKEN_B)
        ) {
            revert Pair__InvalidTokenToSwapTo();
        }
        bool isSwappingToA = swappingTo == address(I_TOKEN_A);
        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            uint256 reserveIn,
            uint256 reserveOut
        ) = isSwappingToA
                ? (I_TOKEN_B, I_TOKEN_A, reserveB, reserveA)
                : (I_TOKEN_A, I_TOKEN_B, reserveA, reserveB);

        if (reserveIn == 0 || reserveOut == 0) {
            revert Pair__InsufficientLiquidityInPool();
        }

        uint256 balanceIn = tokenIn.balanceOf(address(this));
        uint256 actualAmountIn = balanceIn - reserveIn;
        if (actualAmountIn == 0) revert Pair__InsufficientAmountInAfterTransfer();
        if (actualAmountIn < amountIn) revert Pair__AmountInMismatch();
        uint256 amountInWithFee = (actualAmountIn * (BASE - FEE)) / BASE;
        amountOut =
            (amountInWithFee * reserveOut) /
            (reserveIn + amountInWithFee);
        if (amountOut < minAmountOut) revert Pair__InsufficientOutputAmount();
        if (amountOut == 0) revert Pair__AmountOutMustBeGreaterThanZero();
        if (amountOut >= reserveOut) revert Pair__NotEnoughLiquidityForTrade();

        uint256 newReserveA;
        uint256 newReserveB;
        if (isSwappingToA) {
            newReserveA = reserveA - amountOut;
            newReserveB = reserveB + actualAmountIn;
        } else {
            newReserveA = reserveA + actualAmountIn;
            newReserveB = reserveB - amountOut;
        }

        if (newReserveA * newReserveB < reserveA * reserveB) {
            revert Pair__KInvariantViolation();
        }

        reserveA = newReserveA;
        reserveB = newReserveB;
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
        if (to == address(0)) revert Pair__TransferToZeroAddress();
        if (balances[from] < amount) revert Pair__InsufficientBalance();
        if (from != msg.sender) {
            if (allowance[from][msg.sender] < amount) {
                revert Pair__InsufficientAllowance();
            }
            allowance[from][msg.sender] -= amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        balances[from] -= amount;
        balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert Pair__TransferToZeroAddress();
        if (balances[msg.sender] < amount) revert Pair__InsufficientBalance();
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
        if (amountOut == 0) revert Pair__AmountOutMustBeGreaterThanZero();
        if (tokenOut != address(I_TOKEN_A) && tokenOut != address(I_TOKEN_B)) {
            revert Pair__InvalidTokenOutAddress();
        }

        bool isTokenOutA = tokenOut == address(I_TOKEN_A);
        (uint256 reserveIn, uint256 reserveOut) = isTokenOutA
            ? (reserveB, reserveA)
            : (reserveA, reserveB);
        if (reserveIn == 0 || reserveOut == 0) {
            revert Pair__InsufficientLiquidityInPool();
        }
        if (amountOut >= reserveOut) revert Pair__InsufficientLiquidity();

        uint256 numerator = (reserveIn * amountOut);
        uint256 denominator = (reserveOut - amountOut) * (BASE - FEE);
        amountIn = (numerator * BASE) / denominator + 1;

        return amountIn;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}
