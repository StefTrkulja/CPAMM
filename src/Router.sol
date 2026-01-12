// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Factory} from "./Factory.sol";
import {Pair} from "./Pair.sol";

contract Router {
    using SafeERC20 for IERC20;
    Factory public immutable FACTORY;

    // Prvobitno sam koristio require za proveru uslova, ali sam ih zamenio sa custom greskama radi gas optimizacije
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

    // Prima adresu Factory kontrakta prilikom deploy-a, kako bi mogao da pristupi postojećim parovima
    constructor(address factoryAddress) {
        FACTORY = Factory(factoryAddress);
    }

    // ensure sluzi da proveri da li je transakcija istekla, user postavlja deadline da bi sprecio frontrunning napade
    modifier ensure(uint256 deadline) {
        _ensure(deadline);
        _;
    }

    function _ensure(uint256 deadline) internal view {
        if (deadline < block.timestamp) revert Router__Expired();
    }

    /*
    Funkcija za dodavanje liquiditya u par
    tokenA = adresa prvog tokena
    tokenB = adresa drugog tokena
    amountADesired = zeljena kolicina prvog tokena za dodavanje
    amountBDesired = zeljena kolicina drugog tokena za dodavanje
    amountAMin = minimalna kolicina prvog tokena koja se prihvata
    amountBMin = minimalna kolicina drugog tokena koja se prihvata, amoumtAmin i amountBmin sluze za zastitu od slippage-a
    to = adresa korisnika koji ce dobiti LP tokene
    deadline = vremenski rok do kog transakcija mora biti izvrsena, zbog frontrunninga
    */
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
        // Provera da li je adresa primaoca validna, ne sme biti nula adresa
        if (to == address(0)) revert Router__InvalidToAddress();

        // Dobijanje adrese para iz Factory kontrakta
        address pairAddress = FACTORY.getPair(tokenA, tokenB);
        if (pairAddress == address(0)) revert Router__PairNotExist();

        // Izracunavanje optimalnih kolicina tokena koje treba dodati u par
        (amountA, amountB) = calculateLiquidityAmounts(
            pairAddress,
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        /* 
        Transfer tokena od korisnika do Pair kontrakta 
        safeTransferFrom interno proverava da li je korisnik odobrio, da li ima dovoljno tokena i da li je transfer uspesan, jer neki tokeni ne vracaju bool vrednost
        */

        IERC20(tokenA).safeTransferFrom(msg.sender, pairAddress, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pairAddress, amountB);

        // Pair contract ocekuje da su token0 i token1 sortirani po adresi, pa ih sortiramo pre poziva addLiquidity funkcije
        (uint256 amount0, uint256 amount1) = tokenA < tokenB
            ? (amountA, amountB)
            : (amountB, amountA);
        shares = Pair(pairAddress).addLiquidity(amount0, amount1, to);

        return (amountA, amountB, shares);
    }

    /*
    Funkcija za sklanjanje liquiditya iz para
    tokenA = adresa prvog tokena
    tokenB = adresa drugog tokena
    shares = kolicina LP tokena koje korisnik zeli da skloni
    amountAMin = minimalna kolicina prvog tokena koja se prihvata
    amountBMin = minimalna kolicina drugog tokena koja se prihvata (opet zbog slippage)
    to = adresa korisnika koji ce dobiti uklonjene tokene
    deadline = vremenski rok do kog transakcija mora biti izvrsena, zbog frontrunninga
    */

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 shares,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        //Validacija
        if (to == address(0)) revert Router__InvalidToAddress();

        // Dobijanje adrese para iz Factory contracta
        address pairAddress = FACTORY.getPair(tokenA, tokenB);
        if (pairAddress == address(0)) revert Router__PairNotExist();
        // Provera da li korisnik ima dovoljno LP tokena i da li je odobrio Router-u da ih skine
        if (shares == 0) revert Router__InsufficientShares();
        if (Pair(pairAddress).allowance(msg.sender, address(this)) < shares) {
            revert Router__InsufficientAllowance();
        }
        if (!Pair(pairAddress).transferFrom(msg.sender, pairAddress, shares)) {
            revert Router__TransferFailed();
        }
        // Pozivanje funkcije za uklanjanje liquiditya iz Pair contracta
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

    /*
    Internal funkcija za izracunavanje optimalnih kolicina tokena koje treba dodati u par
    */
    function calculateLiquidityAmounts(
        address pairAddress,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        // Dobijanje trenutnih rezervi iz Pair contracta
        (uint256 reserve0, uint256 reserve1) = Pair(pairAddress).getReserves();

        //sortiranje kolicina i adresa tokena kako bi se uskladile sa redosledom u Pair contractu
        (uint256 amountADesiredSorted, uint256 amountBDesiredSorted) = tokenA <
            tokenB
            ? (amountADesired, amountBDesired)
            : (amountBDesired, amountADesired);
        (uint256 amountAMinSorted, uint256 amountBMinSorted) = tokenA < tokenB
            ? (amountAMin, amountBMin)
            : (amountBMin, amountAMin);

        uint256 amount0;
        uint256 amount1;
        /*
        Ako su rezerve nula, dodaju se zeljene kolicine, inace se izracunavaju optimalne kolicine na osnovu trenutnih rezervi. Racuna se
        optimalna kolicina drugog tokena na osnovu zeljene kolicine prvog tokena i trenutnih rezervi, 
        da bi ocuvala ratio. 
        npr: 
        Pool trenutno ima 10ETH i 20k USDC (ratio 1:2000)
        Optimalna kolicina USDC koja odgovara 1 ETH je 2000 USDC, pa ce se dodati 1 ETH i 2000 USDC.
        */
        if (reserve0 == 0 && reserve1 == 0) {
            amount0 = amountADesiredSorted;
            amount1 = amountBDesiredSorted;
        } else {
            uint256 amount1Optimal = (amountADesiredSorted * reserve1) /
                reserve0;
            if (amount1Optimal <= amountBDesiredSorted) {
                // Provera da li je izracunata optimalna kolicina veca od minimalno prihvatljive
                if (amount1Optimal < amountBMinSorted) {
                    revert Router__InsufficientBAmount();
                }
                amount0 = amountADesiredSorted;
                amount1 = amount1Optimal;
            } else {
                // Izracunavanje optimalne kolicine prvog tokena na osnovu zeljene kolicine drugog tokena
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

    /*

    Funkcija za swap tacno odredjene kolicine tokena za drugi token
    tokenIn = adresa tokena koji se salje u swap
    tokenOut = adresa tokena koji se zeli dobiti
    amountIn = kolicina tokena koji se salje u swap
    amountOutMin = minimalna kolicina output tokena, slippage protection
    to = adresa korisnika koji ce dobiti zeljene tokene
    deadline = vremenski rok do kog transakcija mora biti izvrsena, zbog frontrunninga
    */
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountOut) {
        // Validacija
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

    /*
    Funkcija za swap tacno odredjene kolicine output tokena
    tokenIn = adresa tokena koji se salje u swap
    tokenOut = adresa tokena koji se zeli dobiti
    amountOut = kolicina tokena koja se zeli dobiti iz swapa
    amountInMax = maksimalna kolicina input tokena koja se prihvata,
    to = adresa korisnika koji ce dobiti zeljene tokene
    deadline = vremenski rok do kog transakcija mora biti izvrsena, zbog frontrunninga
    */
    function swapTokensToExactTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountIn) {
        // Validacija
        if (to == address(0)) revert Router__InvalidToAddress();
        if (amountOut == 0) revert Router__InsufficientOutputAmount();
        address pairAddress = FACTORY.getPair(tokenIn, tokenOut);
        if (pairAddress == address(0)) revert Router__PairNotExist();

        // Izracunavanje potrebne kolicine input tokena za zeljenu kolicinu output tokena
        amountIn = Pair(pairAddress).getAmountIn(amountOut, tokenOut);
        if (amountIn > amountInMax) revert Router__ExcessiveInputAmount();

        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddress, amountIn);

        uint256 actualAmountOut = Pair(pairAddress).swap(
            amountIn,
            amountOut,
            tokenOut,
            to
        );
        if (actualAmountOut < amountOut)
            revert Router__InsufficientOutputAmount();

        return amountIn;
    }
}
