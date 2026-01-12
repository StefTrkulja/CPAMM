// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {MathLib} from "../lib/MathLib.sol";

contract Pair is ReentrancyGuard {
    // omogucava mi da koristim safeTransfer funkciju iz SafeERC20 biblioteke
    using SafeERC20 for IERC20;

    // Konstante za fee, base i minimum liquidity. Ne mogu zakucati 0.97 jer solidity ne podrzava decimalne brojeve
    uint256 public constant FEE = 30;
    uint256 public constant BASE = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    //Dodati su tokenA i tokenB kao immutable varijable jer se postavljaju samo jednom u konstruktoru, a i smanjuje gas cost
    IERC20 public immutable I_TOKEN_A;
    uint256 public reserveA;

    IERC20 public immutable I_TOKEN_B;
    uint256 public reserveB;

    //totalSupply i balances za LP tokene, kao i allowance mapping za approve i transferFrom funkcionalnost
    uint256 public totalSupply;
    // koliko LP tokena ima svaki korisnik
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;

    // Eventi za Swap, Mint, Burn, Sync, Transfer i Approval
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

    // Prvobitno sam koristio require za proveru uslova, ali sam ih zamenio sa custom greskama radi gas optimizacije
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

    // Konstruktor kog poziva Factory prilikom kreiranja novog para tokena, postavlja tokenA i tokenB kao immutable varijable
    constructor(address _tokenA, address _tokenB) {
        I_TOKEN_A = IERC20(_tokenA);
        I_TOKEN_B = IERC20(_tokenB);
    }

    /*
    Funkcija za dodavanje likvidnosti u LP pool.
    Koristi nonReentrant modifier iz ReentrancyGuarda da spreci reentrancy napade.
    amountA = kolicina tokenA koja se dodaje
    amountB = kolicina tokenB koja se dodaje
    to = adresa korisnika koji dodaje likvidnost i kome se mintuju LP tokeni
    Vraca kolicinu mintovanih LP tokena (sharesMinted).
    */
    function addLiquidity(
        uint256 amountA,
        uint256 amountB,
        address to
    ) external nonReentrant returns (uint256 sharesMinted) {
        // proveravaa da li su obe kolicine > 0
        if (amountA == 0 || amountB == 0)
            revert Pair__AmountsMustBeGreaterThanZero();

        // Proveraju se stvarne kolicine tokena koje su transferovane na ovaj ugovor
        uint256 balanceA = I_TOKEN_A.balanceOf(address(this));
        uint256 balanceB = I_TOKEN_B.balanceOf(address(this));
        uint256 actualAmountA = balanceA - reserveA;
        uint256 actualAmountB = balanceB - reserveB;
        // Validacija
        if (actualAmountA < amountA || actualAmountB < amountB) {
            revert Pair__InsufficientTokensTransferred();
        }
        if (actualAmountA == 0 || actualAmountB == 0)
            revert Pair__NoTokensReceived();

        // Izracunavanje kolicine LP tokena koje treba mintovati
        // Ako je totalSupply 0, koristi se sqrt formula za pocetnu likvidnost, sprecavanje maniplucacije cenom
        if (totalSupply == 0) {
            sharesMinted = MathLib.sqrt(actualAmountA * actualAmountB);
            if (sharesMinted <= MINIMUM_LIQUIDITY) {
                revert Pair__InsufficientLiquidityMinted();
            }
            // Zakljucavanje minimalne likvidnosti, sprecava da prvi napad gde  prvi korisnik dobija ogromnu kontrolu nad pool (udeo)
            mint(address(0), MINIMUM_LIQUIDITY);
            sharesMinted -= MINIMUM_LIQUIDITY;
        } else {
            uint256 shareA = (actualAmountA * totalSupply) / reserveA;
            uint256 shareB = (actualAmountB * totalSupply) / reserveB;
            // Uzima se minimum da se ocuva proprcionalnost izmedju tokena u poolu
            sharesMinted = MathLib.min(shareA, shareB);
        }
        // Validacija
        if (sharesMinted == 0) revert Pair__InsufficientLiquidityMinted();
        if (to == address(0)) revert Pair__InvalidAddress();
        if (to == address(this)) revert Pair__CannotMintToPair();

        // Finalizacija mintovanja LP tokena, koristio sam CEI pattern, pa se prvo mintuju tokeni, pa se azuriraju rezerve i na kraju emituje event
        mint(to, sharesMinted);

        reserveA = balanceA;
        reserveB = balanceB;

        emit Mint(to, actualAmountA, actualAmountB, sharesMinted);
        emit Sync(reserveA, reserveB);

        return sharesMinted;
    }

    /* 
    Funkcija za uklanjanje liquidity-a iz LP pool-a, koristi nonReentrant modifier iz ReentrancyGuarda
    shares = kolicina LP tokena koje korisnik burnuje
    from = adreas korisnika koji uklanja liquidity i kome se vracaju tokeni koje je prethodno dodao
    Vraca kolicine tokenA i tokenB koje su vracene korisniku.
    */
    function removeLiquidity(
        uint256 shares,
        address from
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (shares == 0) revert Pair__SharesMustBeGreaterThanZero();
        uint256 shareBalance = balances[address(this)];
        if (shareBalance < shares) revert Pair__InsufficientSharesReceived();

        // Izracunavanje kolicina tokenA i tokenB koje korisnik dobija nazad
        amountA = (shares * reserveA) / totalSupply;
        amountB = (shares * reserveB) / totalSupply;
        // Validacija
        if (amountA == 0 || amountB == 0)
            revert Pair__InsufficientAmountsToWithdraw();
        if (amountA > reserveA || amountB > reserveB) {
            revert Pair__InsufficientReserves();
        }
        // Finalizacija uklanjanja likvidnosti, koristi se CEI pattern
        burn(address(this), shares);
        reserveA -= amountA;
        reserveB -= amountB;
        I_TOKEN_A.safeTransfer(from, amountA);
        I_TOKEN_B.safeTransfer(from, amountB);

        emit Burn(from, amountA, amountB, shares);
        emit Sync(reserveA, reserveB);
        return (amountA, amountB);
    }

    // Interna funkcija za mintovanje LP tokena
    function mint(address to, uint256 shares) private {
        balances[to] += shares;
        totalSupply += shares;
        emit Transfer(address(0), to, shares);
    }

    // Interna funkcija za burnovanje LP tokena
    function burn(address from, uint256 shares) private {
        if (balances[from] < shares) revert Pair__InsufficientBalanceToBurn();
        balances[from] -= shares;
        totalSupply -= shares;
        emit Transfer(from, address(0), shares);
    }

    /*
    Funkcija za zamenu tokena unutar para
    amountIn = kolicina tokena koja se salje u zamenu
    minAmountOut = minimalna kolicina output tokena, da se spreci slippage 
    swappingTo = adresa tokena koji korisnik zeli da dobije
    to = adresa korisnika koji prima output tokene
    */
    function swap(
        uint256 amountIn,
        uint256 minAmountOut,
        address swappingTo,
        address to
    ) external nonReentrant returns (uint256 amountOut) {
        // Validacija
        if (amountIn == 0) revert Pair__AmountInMustBeGreaterThanZero();
        if (
            swappingTo != address(I_TOKEN_A) && swappingTo != address(I_TOKEN_B)
        ) {
            revert Pair__InvalidTokenToSwapTo();
        }
        /*
         Odredjivanje input i output tokena i njihovih rezervi, na osnovu toga swappginTo adrese. Inicijalno sam koristio if-else, 
        ali sam zamenio ternarnim operatorom radi gas optimizacije
        */
        bool isSwappingToA = swappingTo == address(I_TOKEN_A);
        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            uint256 reserveIn,
            uint256 reserveOut
        ) = isSwappingToA
                ? (I_TOKEN_B, I_TOKEN_A, reserveB, reserveA)
                : (I_TOKEN_A, I_TOKEN_B, reserveA, reserveB);

        // Provera likvidnosti u poolu
        if (reserveIn == 0 || reserveOut == 0) {
            revert Pair__InsufficientLiquidityInPool();
        }
        // PROVERA stvarne kolicine tokena koje su transferovane na ovaj ugovor, jer moze da se desi da se transferuju tokeni koji imaju transfer fee
        uint256 balanceIn = tokenIn.balanceOf(address(this));
        uint256 actualAmountIn = balanceIn - reserveIn;
        if (actualAmountIn == 0)
            revert Pair__InsufficientAmountInAfterTransfer();
        if (actualAmountIn < amountIn) revert Pair__AmountInMismatch();
        // CPAMM formula za izracunavanje output kolicine uzimajuci u obzir fee
        uint256 amountInWithFee = (actualAmountIn * (BASE - FEE)) / BASE;
        amountOut =
            (amountInWithFee * reserveOut) /
            (reserveIn + amountInWithFee);
        //slippage zastita
        if (amountOut < minAmountOut) revert Pair__InsufficientOutputAmount();
        if (amountOut == 0) revert Pair__AmountOutMustBeGreaterThanZero();
        if (amountOut >= reserveOut) revert Pair__NotEnoughLiquidityForTrade();

        /*
        Azuriranje rezervi nakon swap-a koristeci CEI pattern, kao i K invariant provera. 
        osnova je da k = x 8 y ne sme opadati nakon swap-a (k treba da ostane konstantno ili raste(uz fee))
        */
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

    // Getter funkcija, ruter je koristi za dobijanje optimalnih kolicina pre dodavanja likvidnosti
    function getReserves()
        external
        view
        returns (uint256 _reserveA, uint256 _reserveB)
    {
        _reserveA = reserveA;
        _reserveB = reserveB;
    }

    // ERC20 funkcionalnosti za LP tokene: transfer, transferFrom, approve, balanceOf
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

    // Funkcija za izracunavanje potrebne kolicine input tokena da se dobije zeljena kolicina output tokena, ivernzna CPAMM formula
    function getAmountIn(
        uint256 amountOut,
        address tokenOut
    ) external view returns (uint256 amountIn) {
        // Validacija
        if (amountOut == 0) revert Pair__AmountOutMustBeGreaterThanZero();
        if (tokenOut != address(I_TOKEN_A) && tokenOut != address(I_TOKEN_B)) {
            revert Pair__InvalidTokenOutAddress();
        }

        // Odredjivanje rezervi na osnovu tokenOut adrese, koristi se ternarni operator radi gas optimizacije
        bool isTokenOutA = tokenOut == address(I_TOKEN_A);
        (uint256 reserveIn, uint256 reserveOut) = isTokenOutA
            ? (reserveB, reserveA)
            : (reserveA, reserveB);
        if (reserveIn == 0 || reserveOut == 0) {
            revert Pair__InsufficientLiquidityInPool();
        }
        if (amountOut >= reserveOut) revert Pair__InsufficientLiquidity();
        // Inverzna CPAMM formula za izracunavanje potrebne kolicine input tokena
        uint256 numerator = (reserveIn * amountOut);
        uint256 denominator = (reserveOut - amountOut) * (BASE - FEE);
        amountIn = (numerator * BASE) / denominator + 1;

        return amountIn;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}
