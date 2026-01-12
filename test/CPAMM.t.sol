// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Factory} from "../src/Factory.sol";
import {Pair} from "../src/Pair.sol";
import {Router} from "../src/Router.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MathLib} from "../lib/MathLib.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract CPAMMTest is Test {
		using SafeERC20 for ERC20Mock;	
    Factory public factory;
    Router public router;
    Pair public pair;
    
    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    
    address public user1;
    address public user2;
    address public liquidityProvider;
    
    uint256 constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 constant LIQUIDITY_AMOUNT_A = 1000 * 10**18;
    uint256 constant LIQUIDITY_AMOUNT_B = 1000 * 10**18;
    uint256 constant MINIMUM_LIQUIDITY = 1000;
    
    function setUp() external {

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        liquidityProvider = makeAddr("liquidityProvider");
        
        factory = new Factory();
        router = new Router(address(factory));
        
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        
        tokenA.mint(user1, INITIAL_BALANCE);
        tokenB.mint(user1, INITIAL_BALANCE);
        
				tokenA.mint(user2, INITIAL_BALANCE);
        tokenB.mint(user2, INITIAL_BALANCE);
       
			  tokenA.mint(liquidityProvider, INITIAL_BALANCE);
        tokenB.mint(liquidityProvider, INITIAL_BALANCE);
        
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddress);
    }

    // FACTORY ******************************************************************************************************************************************


    // provera da li getPair vraca ispravnu adresu Pair contracta nakon kreiranja istog
    function testFactory__CreatePairSuccess() external view {
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        assertEq(pairAddress, address(pair));
    }
	  // proverava da li Factory emituje odgovarajuci event (PairCreated) kada se kreira novi Pair
    function testFactory__CreatePairEmitsEvent() external {
        ERC20Mock tokenC = new ERC20Mock();
        
        vm.expectEmit(true, true, false, false);
        emit Factory.PairCreated(address(tokenA), address(tokenC), address(0), 0);
        
        address newPair = factory.createPair(address(tokenA), address(tokenC));
        assertTrue(newPair != address(0));
    }
	// provera da li getPair vraca ispravnu adresu Pair contracta
    function testFactory__GetPairReturnsCorrectAddress() external view {
        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        assertEq(pairAddress, address(pair));
    }
	// provera da li allPairsLength vraca ispravan broj kreiranih Pair contracta
    function testFactory__AllPairsReturnsCorrectLength() external view {
        uint256 length = factory.allPairsLength();
        assertEq(length, 1);
    }
 // proverava da li je moguce kreirati Pair sa istim adresama tokena i da li pravilno revertuje
    function testFactory__CreatePairIdenticalAddressesReverts() external {
        vm.expectRevert(Factory.Factory__IdenticalAddresses.selector);
        factory.createPair(address(tokenA), address(tokenA));
    }
// proverava da li je moguce kreirati pair sa zero adresom i da li pravilno revertuje
    function testFactory__CreatePairZeroAddressReverts() external {
        vm.expectRevert(Factory.Factory__ZeroAddress.selector);
        factory.createPair(address(0), address(tokenB));
    }
// proverava da li korisnik moze da kreira par koji vec postoji i da li pravilno revertuje
    function testFactory__CreatePairPairExistsReverts() external {
        vm.expectRevert(Factory.Factory__PairExists.selector);
        factory.createPair(address(tokenA), address(tokenB));
    }
// proverava da li getPair vraca ispravnu adresu Pair contracta kada se tokeni proslede u obrnutom redosledu, getPair(A,B) = getPair(B,A)
    function testFactory__GetPairReverseOrder() external view {
        address pairAddress1 = factory.getPair(address(tokenA), address(tokenB));
        address pairAddress2 = factory.getPair(address(tokenB), address(tokenA));
        assertEq(pairAddress1, pairAddress2);
    }
// proverava da li je moguce kreirati vise parova i da li allPairsLength vraca ispravan broj kreiranih parova
    function testFactory__CreateMultiplePairs() external {
        ERC20Mock tokenC = new ERC20Mock();
        address pairAddress2 = factory.createPair(address(tokenA), address(tokenC));
        
        assertTrue(pairAddress2 != address(0));
        assertEq(factory.allPairsLength(), 2);
    }

    // PAIR ******************************************************************************************************************************************
// Proverava da li su pocetne rezerve para nula
    function testPair__InitialReservesAreZero() external view {
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();
        assertEq(reserveA, 0);
        assertEq(reserveB, 0);
    }
// Proverava da li je pocetni total supply LP tokena nula pre mintovanja
    function testPair__InitialTotalSupplyIsZero() external view {
        assertEq(pair.totalSupply(), 0);
    }
// Proverava da li su tokenA i tokenB nepromenljive adrese
    function testPair__TokensAreImmutable() external view {
        assertEq(pair.tokenA(), address(tokenA));
        assertEq(pair.tokenB(), address(tokenB));
    }

    // PAIR TESTS - ADD LIQUIDITY ***********************************************************************************************************************

		// proverava da li prvi LP dobija ispravan iznos LP tokena prilikom dodavanja likvidnosti, sqrt(amountA * amountB) - MINIMUM_LIQUIDITY. 
    function testPair__FirstLiquidityProviderMinting() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        
        uint256 lpTokensMinted = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();
        assertEq(reserveA, LIQUIDITY_AMOUNT_A);
        assertEq(reserveB, LIQUIDITY_AMOUNT_B);
        
        uint256 expectedLp = MathLib.sqrt(LIQUIDITY_AMOUNT_A * LIQUIDITY_AMOUNT_B) - MINIMUM_LIQUIDITY;
        assertEq(lpTokensMinted, expectedLp);
        assertEq(pair.balanceOf(liquidityProvider), expectedLp);
        assertEq(pair.totalSupply(), expectedLp + MINIMUM_LIQUIDITY);
        
        vm.stopPrank();
    }
		// Proverava se da li sledeci LPovi dobijaju ispravan iznos LP tokena prilikom dodavanja likvidnosti
    function testPair__SubsequentLiquidityProviderMinting() external {
        vm.startPrank(user1);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 amountA = LIQUIDITY_AMOUNT_A / 2;
        uint256 amountB = LIQUIDITY_AMOUNT_B / 2;
        tokenA.safeTransfer(address(pair), amountA);
        tokenB.safeTransfer(address(pair), amountB);
        
        uint256 totalSupply = pair.totalSupply();
        uint256 expectedLp = MathLib.min((amountA * totalSupply) / LIQUIDITY_AMOUNT_A, (amountB * totalSupply) / LIQUIDITY_AMOUNT_B);
        
        uint256 secondLp = pair.addLiquidity(amountA, amountB, user2);
        
        assertEq(secondLp, expectedLp);
        assertEq(pair.balanceOf(user2), expectedLp);
        
        vm.stopPrank();
    }

   // Proverava da li addLiquidity emituje odgovarajuci event (Mint) sa ispravnim parametrima
    function testPair__MintEmitsCorrectEvents() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        
        vm.expectEmit(true, false, false, false);
        emit Pair.Mint(liquidityProvider, 0, 0, 0);
        
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        vm.stopPrank();
    }
	// Proverava da li se reserveA i reserveB pravilno azuriraju nakon dodavanja likvidnosti
    function testPair__UpdateReservesAfterMint() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();
        assertEq(reserveA, LIQUIDITY_AMOUNT_A);
        assertEq(reserveB, LIQUIDITY_AMOUNT_B);
        
        vm.stopPrank();
    }

	//Proverava da li se mintuje ispravan iznos LP tokena prilikom dodavanja likvidnosti
    function testPair__MintsCorrectLPAmount() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        
        uint256 expectedLp = MathLib.sqrt(LIQUIDITY_AMOUNT_A * LIQUIDITY_AMOUNT_B) - MINIMUM_LIQUIDITY;
        uint256 actualLp = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        assertEq(actualLp, expectedLp);
        
        vm.stopPrank();
    }

		// Proverava da li je prvih 1000 lp tokena zakljucano (locked) na zero adresi
    function testPair__LockMinimumLiquidity() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);

        assertEq(pair.balanceOf(address(0)), MINIMUM_LIQUIDITY);
        
        vm.stopPrank();
    }

    // PAIR - ADD LIQUIDITY ERRORS ********************************************************************************************************
	
		// proverava da korisnik ne moe dodati likvidnosst sa nula kolicinama tokena i da li pravilno revertuje
    function testPair__MintWithZeroAmountsReverts() external {
        vm.startPrank(liquidityProvider);
        
        vm.expectRevert(Pair.Pair__AmountsMustBeGreaterThanZero.selector);
        pair.addLiquidity(0, 0, liquidityProvider);
        
        vm.stopPrank();
    }
		// proverava da ne mozes mintovati ako je poslato premalo tokenA ili tokenB i da li pravilno revertuje
    function testPair__InsufficientLiquidityMintedReverts() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), 100);
        tokenB.safeTransfer(address(pair), 100);
        
        vm.expectRevert(Pair.Pair__InsufficientLiquidityMinted.selector);
        pair.addLiquidity(100, 100, liquidityProvider);
        
        vm.stopPrank();
    }
		// proverava da ne mogu da se mintuju tokeni na zro adresu i da li pravilno revertuje
    function testPair__MintToZeroAddressReverts() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        
        vm.expectRevert(Pair.Pair__InvalidAddress.selector);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, address(0));
        
        vm.stopPrank();
    }

    // PAIR TESTS - REMOVE LIQUIDITY ********************************************************************************************************
		// Proverava se da korisnik moze uspesno da burnuje tokene i da dobije nazad odgovarajucu kolicinu tokenA i tokenB
    function testPair__BurnLiquidityTokens() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        uint256 lpTokens = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        uint256 burnAmount = lpTokens / 2;
        assertTrue(pair.transfer(address(pair), burnAmount));
        
        (uint256 amountA, uint256 amountB) = pair.removeLiquidity(burnAmount, liquidityProvider);
        
        assertGt(amountA, 0);
        assertGt(amountB, 0);
        assertEq(pair.balanceOf(liquidityProvider), lpTokens - burnAmount);
        
        vm.stopPrank();
    }

	// Proverava da burn vraca ispravan iznos tokenA i tokenB na osnovu formule (burnAmount * reserve) / totalSupply
    function testPair__ReturnsCorrectAmountsOnBurn() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        uint256 lpTokens = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        uint256 burnAmount = lpTokens / 2;
        assertTrue(pair.transfer(address(pair), burnAmount));
        
        uint256 totalSupply = pair.totalSupply();
        uint256 expectedAmountA = (burnAmount * LIQUIDITY_AMOUNT_A) / totalSupply;
        uint256 expectedAmountB = (burnAmount * LIQUIDITY_AMOUNT_B) / totalSupply;
        
        (uint256 amountA, uint256 amountB) = pair.removeLiquidity(burnAmount, liquidityProvider);
        
        assertApproxEqAbs(amountA, expectedAmountA, 1);
        assertApproxEqAbs(amountB, expectedAmountB, 1);
        
        vm.stopPrank();
    }

// provera da se rezerve smanjuju ispravno nakon uklanjanja likvidnosti
    function testPair__UpdateReservesAfterBurn() external {
        vm.startPrank(liquidityProvider);
        
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        uint256 lpTokens = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        uint256 burnAmount = lpTokens / 2;
        assertTrue(pair.transfer(address(pair), burnAmount));
        
        (uint256 amountA, uint256 amountB) = pair.removeLiquidity(burnAmount, liquidityProvider);
        
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();
        assertEq(reserveA, LIQUIDITY_AMOUNT_A - amountA);
        assertEq(reserveB, LIQUIDITY_AMOUNT_B - amountB);
        
        vm.stopPrank();
    }

    // PAIR - REMOVE LIQUIDITY ERRORS ********************************************************************************************************

	// Proverava da li burn sa nulom tokena revertuje
    function testPair__BurnWithZeroSharesReverts() external {
        vm.expectRevert(Pair.Pair__SharesMustBeGreaterThanZero.selector);
        pair.removeLiquidity(0, liquidityProvider);
    }

  //proverava da ne mozes burnovati vise tokena nego sto imas i da li pravilno revertuje
    function testPair__InsufficientBalanceReverts() external {
        vm.startPrank(liquidityProvider);
        
        vm.expectRevert(Pair.Pair__InsufficientSharesReceived.selector);
        pair.removeLiquidity(1000, liquidityProvider);
        
        vm.stopPrank();
    }

    // PAIR - SWAP ********************************************************************************************************
   // sledeca 2 proveravaju da li swap radi kako treba za oba smera (tokenA za tokenB i obrnuto) i da li korisnik dobija ispravan iznos tokena nakon swapa
    function testPair__SwapExactAForB() external {
     
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 amountIn = 100 * 10**18;
        tokenA.safeTransfer(address(pair), amountIn);
        
        uint256 balanceBefore = tokenB.balanceOf(user1);
        uint256 amountOut = pair.swap(amountIn, 1, address(tokenB), user1);
        uint256 balanceAfter = tokenB.balanceOf(user1);
        
        assertGt(amountOut, 0);
        assertEq(balanceAfter - balanceBefore, amountOut);
        
        vm.stopPrank();
    }

    function testPair__SwapExactBForA() external {

        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 amountIn = 100 * 10**18;
        tokenB.safeTransfer(address(pair), amountIn);
        
        uint256 balanceBefore = tokenA.balanceOf(user1);
        uint256 amountOut = pair.swap(amountIn, 1, address(tokenA), user1);
        uint256 balanceAfter = tokenA.balanceOf(user1);
        
        assertGt(amountOut, 0);
        assertEq(balanceAfter - balanceBefore, amountOut);
        
        vm.stopPrank();
    }
		// Proverava da se rezerve pravilno azuriraju nakon swapa
    function testPair__UpdateReservesAfterSwap() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 amountIn = 100 * 10**18;
        tokenA.safeTransfer(address(pair), amountIn);
        
        uint256 amountOut = pair.swap(amountIn, 1, address(tokenB), user1);
        
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();
        assertEq(reserveA, LIQUIDITY_AMOUNT_A + amountIn);
        assertEq(reserveB, LIQUIDITY_AMOUNT_B - amountOut);
        
        vm.stopPrank();
    }
  // Proverava da se naplacuju feejevi prilikom swapa
    function testPair__AppliesFeeOnSwap() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 amountIn = 100 * 10**18;
        tokenA.safeTransfer(address(pair), amountIn);
        
        uint256 amountInWithFee = (amountIn * 970) / 1000;
        uint256 expectedOut = (amountInWithFee * LIQUIDITY_AMOUNT_B) / (LIQUIDITY_AMOUNT_A + amountInWithFee);
        
        uint256 amountOut = pair.swap(amountIn, 1, address(tokenB), user1);
        
        assertEq(amountOut, expectedOut);
        
        vm.stopPrank();
    }
		// Proverava da K invarijanta ne opada nakon swapa(raste(zbog feeja) ili ostaje ista), najbitnija provera!
    function testPair__MaintainsConstantProductInvariant() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        uint256 kBefore = LIQUIDITY_AMOUNT_A * LIQUIDITY_AMOUNT_B;
        
        vm.startPrank(user1);
        uint256 amountIn = 100 * 10**18;
        tokenA.safeTransfer(address(pair), amountIn);
        pair.swap(amountIn, 1, address(tokenB), user1);
        
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();
        uint256 kAfter = reserveA * reserveB;
      
        assertGe(kAfter, kBefore);
        
        vm.stopPrank();
    }

    // PAIR - SWAP ERRORS ********************************************************************************************************
		// Proverava da li swap sa nulom kolicinom ulaznog tokena revertuje
    function testPair__SwapWithZeroAmountInReverts() external {
        vm.expectRevert(Pair.Pair__AmountInMustBeGreaterThanZero.selector);
        pair.swap(0, 1, address(tokenB), user1);
    }

    // Proverava da li swap na nevalidan token revertuje
    function testPair__SwapWithInvalidTokenReverts() external {
        ERC20Mock tokenC = new ERC20Mock();
        
        vm.expectRevert(Pair.Pair__InvalidTokenToSwapTo.selector);
        pair.swap(100, 1, address(tokenC), user1);
    }
		// Proverava da li swap ne moze da se izvrsi ako nema dovoljno likvidnosti u poolu i da li pravilno revertuje
    function testPair__SwapInsufficientLiquidityReverts() external {
        vm.startPrank(user1);
        
        tokenA.safeTransfer(address(pair), 100 * 10**18);
        
        vm.expectRevert(Pair.Pair__InsufficientLiquidityInPool.selector);
        pair.swap(100 * 10**18, 1, address(tokenB), user1);
        
        vm.stopPrank();
    }
   // Proverava da li swap ne moze da se izvrsi ako je trazeni izlazni iznos veci od moguceg i da li pravilno revertuje, slippage
    function testPair__SwapInsufficientOutputAmountReverts() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 amountIn = 1 * 10**18;
        tokenA.safeTransfer(address(pair), amountIn);
        
        vm.expectRevert(Pair.Pair__InsufficientOutputAmount.selector);
        pair.swap(amountIn, 1000 * 10**18, address(tokenB), user1);
        
        vm.stopPrank();
    }

    // PAIR - ERC20 LP TOKENS ********************************************************************************************************
		// Proverava da li korisnik moze da transferise LP tokene izmedju adresa (Router ce koristiti ovu funkcionalnost)
    function testPair__TransferLPTokens() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        uint256 lpTokens = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        uint256 transferAmount = lpTokens / 2;
        assertTrue(pair.transfer(user1, transferAmount));
        
        assertEq(pair.balanceOf(user1), transferAmount);
        assertEq(pair.balanceOf(liquidityProvider), lpTokens - transferAmount);
        
        vm.stopPrank();
    }
	 //Proverava da li korisnik moze da odobri drugom korisniku da trosi njegove LP tokene(Router ce koristiti ovu funkcionalnost)
    function testPair__ApproveLPTokens() external {
        vm.startPrank(liquidityProvider);
        
        pair.approve(user1, 1000 * 10**18);
        
        assertEq(pair.allowance(liquidityProvider, user1), 1000 * 10**18);
        
        vm.stopPrank();
    }
		// Proverava da li korisnik moze da transferise LP tokene koristeci allowance mehanizam
    function testPair__TransferFromLPTokens() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        uint256 lpTokens = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        uint256 transferAmount = lpTokens / 2;
        pair.approve(user1, transferAmount);
        vm.stopPrank();
        
        vm.prank(user1);
        assertTrue(pair.transferFrom(liquidityProvider, user2, transferAmount));
        
        assertEq(pair.balanceOf(user2), transferAmount);
    }
		// Proverava da li transfer emituje odgovarajuci event
    function testPair__TransferEmitsEvent() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(liquidityProvider, user1, 100);
        
        assertTrue(pair.transfer(user1, 100));
        
        vm.stopPrank();
    }

    // Proverava da li approval emituje odgovarajuci event
    function testPair__ApprovalEmitsEvent() external {
        vm.startPrank(liquidityProvider);
        
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(liquidityProvider, user1, 1000);
        
        pair.approve(user1, 1000);
        
        vm.stopPrank();
    }
   // Proverava da li transfer sa nedovoljnim balansom revertuje
    function testPair__TransferInsufficientBalanceReverts() external {
        vm.startPrank(liquidityProvider);
        
        vm.expectRevert();
        (bool success) = pair.transfer(user1, 1000 * 10**18);
        
        vm.stopPrank();
    }
 // Proverava da li transfer na zero adresu revertuje
    function testPair__TransferToZeroAddressReverts() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        vm.expectRevert();
        (bool success) = pair.transfer(address(0), 100);
        
        vm.stopPrank();
    }
    // Proverava da li transferFrom sa nedovoljnim allowance-om revertuje
    function testPair__TransferFromInsufficientAllowanceReverts() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.prank(user1);
        vm.expectRevert();
        (bool success) = pair.transferFrom(liquidityProvider, user2, 100);
    }

    // ROUTER ********************************************************************************************************


     // Proverava da li korisnik moze uspesno da doda likvidnost preko Router-a
    function testRouter__AddLiquiditySuccess() external {
        vm.startPrank(user1);
        
        tokenA.approve(address(router), LIQUIDITY_AMOUNT_A);
        tokenB.approve(address(router), LIQUIDITY_AMOUNT_B);
        
        (uint256 amountA, uint256 amountB, uint256 shares) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            LIQUIDITY_AMOUNT_A,
            LIQUIDITY_AMOUNT_B,
            LIQUIDITY_AMOUNT_A * 9 / 10,
            LIQUIDITY_AMOUNT_B * 9 / 10,
            user1,
            block.timestamp + 300
        );
        
        assertEq(amountA, LIQUIDITY_AMOUNT_A);
        assertEq(amountB, LIQUIDITY_AMOUNT_B);
        assertGt(shares, 0);
        
        vm.stopPrank();
    }
    // Proverava da li korisnik moze uspesno da ukloni likvidnost preko Router-a
    function testRouter__RemoveLiquiditySuccess() external {
        vm.startPrank(user1);
        
        tokenA.approve(address(router), LIQUIDITY_AMOUNT_A);
        tokenB.approve(address(router), LIQUIDITY_AMOUNT_B);
        (,, uint256 shares) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            LIQUIDITY_AMOUNT_A,
            LIQUIDITY_AMOUNT_B,
            0, 0,
            user1,
            block.timestamp + 300
        );
        
        pair.approve(address(router), shares / 2);
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            shares / 2,
            0, 0,
            user1,
            block.timestamp + 300
        );
        
        assertGt(amountA, 0);
        assertGt(amountB, 0);
        
        vm.stopPrank();
    }
   // Proverava da li korisnik moze uspesno da izvrsi swap tacno odredjene kolicine tokenA za tokenB preko Router-a
    function testRouter__SwapExactTokensForTokensSuccess() external {
        vm.startPrank(liquidityProvider);
        tokenA.approve(address(router), LIQUIDITY_AMOUNT_A);
        tokenB.approve(address(router), LIQUIDITY_AMOUNT_B);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            LIQUIDITY_AMOUNT_A,
            LIQUIDITY_AMOUNT_B,
            0, 0,
            liquidityProvider,
            block.timestamp + 300
        );
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 amountIn = 100 * 10**18;
        tokenA.approve(address(router), amountIn);
        
        uint256 balanceBefore = tokenB.balanceOf(user1);
        uint256 amountOut = router.swapExactTokensForTokens(
            address(tokenA),
            address(tokenB),
            amountIn,
            1,
            user1,
            block.timestamp + 300
        );
        
        assertGt(amountOut, 0);
        assertEq(tokenB.balanceOf(user1) - balanceBefore, amountOut);
        
        vm.stopPrank();
    }
		// ROUTER - ERRORS ********************************************************************************************************
		// Proverava da li addLiquidity revertuje ako je prosledjeni deadline istekao
    function testRouter__RevertWhen_DeadlineExpired() external {
        vm.startPrank(user1);
        
        tokenA.approve(address(router), LIQUIDITY_AMOUNT_A);
        tokenB.approve(address(router), LIQUIDITY_AMOUNT_B);
        
        vm.warp(block.timestamp + 1000);
        
        vm.expectRevert(Router.Router__Expired.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            LIQUIDITY_AMOUNT_A,
            LIQUIDITY_AMOUNT_B,
            0, 0,
            user1,
            block.timestamp - 1
        );
        
        vm.stopPrank();
    }
		// Proverava se da li Router moze izvrsiti operaciju ako nema approve za tokenA i tokenB od strane korisnika
    function testRouter__RevertWhen_InsufficientAllowance() external {
        vm.startPrank(user1);
        
        vm.expectRevert();
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            LIQUIDITY_AMOUNT_A,
            LIQUIDITY_AMOUNT_B,
            0, 0,
            user1,
            block.timestamp + 300
        );
        
        vm.stopPrank();
    }

    // SECURITY TESTS ********************************************************************************************************

		// Proverava da li velike kolicine tokena ne izazivaju overflow u Pair contractu tokom dodavanja likvidnosti i swapa
    function testSecurity__NoOverflowOnLargeAmounts() external {

        uint256 largeAmount = 10**30; 
        
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, largeAmount * 2);
        tokenB.mint(liquidityProvider, largeAmount * 2);
        
        tokenA.safeTransfer(address(pair), largeAmount);
        tokenB.safeTransfer(address(pair), largeAmount);
        
        uint256 lpTokens = pair.addLiquidity(largeAmount, largeAmount, liquidityProvider);
        assertGt(lpTokens, 0);
        
        uint256 swapAmount = largeAmount / 10;
        tokenA.safeTransfer(address(pair), swapAmount);
        uint256 amountOut = pair.swap(swapAmount, 1, address(tokenB), liquidityProvider);
        assertGt(amountOut, 0);
        
        vm.stopPrank();
    }
		// proverava da li napadac ne moze da isprazni rezerve poola cak i sa ogromnim swapom zbog slippage zastite
    function testSecurity__CannotDrainReserves() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 attackAmount = LIQUIDITY_AMOUNT_A * 100;
        tokenA.mint(user1, attackAmount);
        tokenA.safeTransfer(address(pair), attackAmount);
        
        vm.expectRevert(Pair.Pair__InsufficientOutputAmount.selector);
        pair.swap(attackAmount, LIQUIDITY_AMOUNT_B, address(tokenB), user1);
        
        vm.stopPrank();
    }
 // Proverava da li K raste ili ostaje isti nakon velikog swapa, sto pokazuje otpornost na manipulaciju cenom
    function testSecurity__PriceManipulationResistance() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        (uint256 reserve0Before, uint256 reserve1Before) = pair.getReserves();
        uint256 kBefore = reserve0Before * reserve1Before;
        
        vm.startPrank(user1);
        uint256 swapAmount = LIQUIDITY_AMOUNT_A / 2;
        tokenA.safeTransfer(address(pair), swapAmount);
        pair.swap(swapAmount, 1, address(tokenB), user1);
        vm.stopPrank();
        
        (uint256 reserve0After, uint256 reserve1After) = pair.getReserves();
        uint256 kAfter = reserve0After * reserve1After;
        assertGt(kAfter, kBefore, "K invariant should increase due to fees");
    }
	// Proverava da li su minimalni LP tokeni zakljucani i ne mogu biti iskorišćeni od strane LP-a
    function testSecurity__MinimumLiquidityLock() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        
        assertEq(pair.balanceOf(address(0)), 1000, "Minimum liquidity not locked");
        
        uint256 totalSupply = pair.totalSupply();
        uint256 lpBalance = pair.balanceOf(liquidityProvider);
        assertLt(lpBalance, totalSupply, "LP should not have all tokens");
        
        vm.stopPrank();
    }
		// Proverava da napadac ne moze da ukrade tokene iz Pair contracta slanjem tokena direktno na njega bez koriscenja swap funkcije
    function testSecurity__CannotStealTokensByDirectTransfer() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 attackAmount = 100 * 10**18;
        tokenA.safeTransfer(address(pair), attackAmount);
        
        vm.expectRevert(Pair.Pair__AmountInMustBeGreaterThanZero.selector);
        pair.swap(0, 1, address(tokenB), user1);
        
        vm.stopPrank();
    }
		// Proverava da li slippage zastita pravilno funkcionise i sprecava velike gubitke tokom swapa
    function testSecurity__SlippageProtection() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 swapAmount = 10 * 10**18;
        tokenA.safeTransfer(address(pair), swapAmount);
        
        vm.expectRevert(Pair.Pair__InsufficientOutputAmount.selector);
        pair.swap(swapAmount, LIQUIDITY_AMOUNT_B / 2, address(tokenB), user1);
        
        vm.stopPrank();
    }
		// Proverava da K invarijanta ne opada nakon vise swap operacija
    function testSecurity__KInvariantValidation() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        uint256 kBefore = LIQUIDITY_AMOUNT_A * LIQUIDITY_AMOUNT_B;
        
        vm.startPrank(user1);
        for (uint i = 0; i < 5; i++) {
            uint256 swapAmount = 5 * 10**18;
            assertTrue(tokenA.transfer(address(pair), swapAmount));
            pair.swap(swapAmount, 1, address(tokenB), user1);
        }
        vm.stopPrank();
        
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();
        uint256 kAfter = reserveA * reserveB;
        
        assertGt(kAfter, kBefore, "K invariant violated");
    }
		// Proverava da korisnik ne moze burnovati tudje LP tokene bez odobrenja
    function testSecurity__NoTokenApprovalBypass() external {
        vm.startPrank(liquidityProvider);
        tokenA.safeTransfer(address(pair), LIQUIDITY_AMOUNT_A);
        tokenB.safeTransfer(address(pair), LIQUIDITY_AMOUNT_B);
        uint256 lpTokens = pair.addLiquidity(LIQUIDITY_AMOUNT_A, LIQUIDITY_AMOUNT_B, liquidityProvider);
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert(Pair.Pair__InsufficientSharesReceived.selector);
        pair.removeLiquidity(lpTokens, user1);
        vm.stopPrank();
    }
   // Proverava da li addLiquidity revertuje ako je prosledjeni deadline istekao
    function testSecurity__RouterDeadlineEnforced() external {
        vm.startPrank(user1);
        tokenA.approve(address(router), LIQUIDITY_AMOUNT_A);
        tokenB.approve(address(router), LIQUIDITY_AMOUNT_B);
        
        vm.warp(block.timestamp + 1000);
        
        vm.expectRevert(Router.Router__Expired.selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            LIQUIDITY_AMOUNT_A,
            LIQUIDITY_AMOUNT_B,
            0, 0,
            user1,
            block.timestamp - 1
        );
        
        vm.stopPrank();
    }
}

