// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract BinaryMarketTest is Test {
    ConditionalTokens public conditionalTokens;
    MockUSDC public usdc;
    BinaryMarket public market;
    MarketFactory public factory;
    
    address public oracle = address(0x1);
    address public trader1 = address(0x2);
    address public trader2 = address(0x3);
    address public liquidityProvider = address(0x4);
    
    string public constant QUESTION = "Will ETH reach $5000 by end of 2025?";
    uint256 public endTime;
    
    function setUp() public {
        // Deploy contracts
        usdc = new MockUSDC();
        factory = new MarketFactory(usdc, address(this));
        conditionalTokens = factory.conditionalTokens();
        
        // Set end time to 30 days from now
        endTime = block.timestamp + 30 days;
        
        // Create market
        address marketAddr = factory.createMarket(oracle, QUESTION, endTime);
        market = BinaryMarket(marketAddr);
        
        // Fund test accounts
        usdc.transfer(trader1, 10000 * 10**6);
        usdc.transfer(trader2, 10000 * 10**6);
        usdc.transfer(liquidityProvider, 100000 * 10**6);
        
        // Approve market for spending
        vm.prank(trader1);
        usdc.approve(address(market), type(uint256).max);
        
        vm.prank(trader2);
        usdc.approve(address(market), type(uint256).max);
        
        vm.prank(liquidityProvider);
        usdc.approve(address(market), type(uint256).max);
    }
    
    function testAddLiquidity() public {
        uint256 liquidityAmount = 10000 * 10**6; // 10k USDC
        
        vm.prank(liquidityProvider);
        uint256 liquidity = market.addLiquidity(liquidityAmount);
        
        assertEq(liquidity, liquidityAmount, "Liquidity tokens mismatch");
        assertEq(market.yesReserve(), liquidityAmount, "YES reserve mismatch");
        assertEq(market.noReserve(), liquidityAmount, "NO reserve mismatch");
        assertEq(market.totalLiquidity(), liquidityAmount, "Total liquidity mismatch");
        assertEq(market.liquidityBalance(liquidityProvider), liquidityAmount, "LP balance mismatch");
    }
    
    function testBuyYesTokens() public {
        // Add liquidity first
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        // Buy YES tokens
        uint256 investmentAmount = 1000 * 10**6; // 1k USDC
        uint256 minTokensOut = 0;
        
        uint256 expectedTokens = market.calcBuyAmount(true, investmentAmount);
        
        vm.prank(trader1);
        uint256 tokensOut = market.buy(true, investmentAmount, minTokensOut);
        
        assertGt(tokensOut, 0, "Should receive tokens");
        assertEq(tokensOut, expectedTokens, "Token amount mismatch");
        
        // Check that YES price increased
        uint256 yesPrice = market.getPrice(true);
        assertGt(yesPrice, 0.5e18, "YES price should be > 50%");
    }
    
    function testBuyNoTokens() public {
        // Add liquidity first
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        // Buy NO tokens
        uint256 investmentAmount = 1000 * 10**6;
        uint256 minTokensOut = 0;
        
        vm.prank(trader1);
        uint256 tokensOut = market.buy(false, investmentAmount, minTokensOut);
        
        assertGt(tokensOut, 0, "Should receive tokens");
        
        // Check that NO price increased (YES price decreased)
        uint256 yesPrice = market.getPrice(true);
        assertLt(yesPrice, 0.5e18, "YES price should be < 50%");
    }
    
    function testSellYesTokens() public {
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        // Buy YES tokens first
        uint256 investmentAmount = 1000 * 10**6;
        vm.prank(trader1);
        uint256 tokensBought = market.buy(true, investmentAmount, 0);
        
        // Approve conditional tokens for selling
        vm.prank(trader1);
        conditionalTokens.setApprovalForAll(address(market), true);
        
        // Sell half of the YES tokens
        uint256 tokensToSell = tokensBought / 2;
        uint256 expectedCollateral = market.calcSellAmount(true, tokensToSell);
        
        vm.prank(trader1);
        uint256 collateralOut = market.sell(true, tokensToSell, 0);
        
        assertEq(collateralOut, expectedCollateral, "Collateral amount mismatch");
        assertGt(collateralOut, 0, "Should receive collateral");
    }
    
    function testPriceImpact() public {
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        // Initial price should be 50/50
        uint256 initialYesPrice = market.getPrice(true);
        assertApproxEqAbs(initialYesPrice, 0.5e18, 0.01e18, "Initial price should be ~50%");
        
        // Large buy should move price significantly
        vm.prank(trader1);
        market.buy(true, 5000 * 10**6, 0);
        
        uint256 newYesPrice = market.getPrice(true);
        assertGt(newYesPrice, 0.65e18, "Price should increase significantly");
    }
    
    function testSlippageProtection() public {
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        // Try to buy with unrealistic slippage protection
        uint256 investmentAmount = 1000 * 10**6;
        uint256 minTokensOut = 2000 * 10**6; // Expecting more than possible
        
        vm.prank(trader1);
        vm.expectRevert("Slippage exceeded");
        market.buy(true, investmentAmount, minTokensOut);
    }
    
    function testCannotTradeAfterEndTime() public {
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        // Move time past end time
        vm.warp(endTime + 1);
        
        // Try to buy
        vm.prank(trader1);
        vm.expectRevert("Market ended");
        market.buy(true, 1000 * 10**6, 0);
    }
    
    function testRemoveLiquidity() public {
        // Add liquidity
        uint256 liquidityAmount = 10000 * 10**6;
        vm.prank(liquidityProvider);
        uint256 liquidity = market.addLiquidity(liquidityAmount);
        
        // Remove liquidity
        vm.prank(liquidityProvider);
        conditionalTokens.setApprovalForAll(address(market), true);
        
        vm.prank(liquidityProvider);
        uint256 amountOut = market.removeLiquidity(liquidity);
        
        assertEq(amountOut, liquidityAmount, "Should get back initial amount");
        assertEq(market.totalLiquidity(), 0, "Total liquidity should be 0");
        assertEq(market.liquidityBalance(liquidityProvider), 0, "LP balance should be 0");
    }
    
    function testMultipleTraders() public {
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(20000 * 10**6);
        
        // Trader1 buys YES
        vm.prank(trader1);
        market.buy(true, 1000 * 10**6, 0);
        
        // Trader2 buys NO
        vm.prank(trader2);
        market.buy(false, 1000 * 10**6, 0);
        
        // Price should be back near 50/50 due to opposite trades
        uint256 yesPrice = market.getPrice(true);
        assertApproxEqAbs(yesPrice, 0.5e18, 0.1e18, "Price should be near 50%");
    }
    
    function testFeeAccumulation() public {
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        uint256 initialFees = market.accumulatedFees();
        
        // Make a trade
        vm.prank(trader1);
        market.buy(true, 1000 * 10**6, 0);
        
        uint256 finalFees = market.accumulatedFees();
        assertGt(finalFees, initialFees, "Fees should accumulate");
        
        // Fee should be 0.1% of investment
        uint256 expectedFee = (1000 * 10**6 * 10) / 10000; // 0.1%
        assertEq(finalFees - initialFees, expectedFee, "Fee amount mismatch");
    }
    
    function testFuzzBuyAmount(uint256 investmentAmount) public {
        vm.assume(investmentAmount > 10**6 && investmentAmount < 1000 * 10**6);
        
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        // Fund trader1 more if needed
        usdc.mint(trader1, investmentAmount);
        
        // Buy YES tokens
        vm.prank(trader1);
        uint256 tokensOut = market.buy(true, investmentAmount, 0);
        
        assertGt(tokensOut, 0, "Should receive tokens");
        assertLt(tokensOut, investmentAmount, "Cannot get more tokens than investment");
    }
    
    function testInvariantConstantProduct() public {
        // Add liquidity
        vm.prank(liquidityProvider);
        market.addLiquidity(10000 * 10**6);
        
        uint256 initialProduct = market.yesReserve() * market.noReserve();
        
        // Make a trade
        vm.prank(trader1);
        market.buy(true, 1000 * 10**6, 0);
        
        uint256 finalProduct = market.yesReserve() * market.noReserve();
        
        // Product should stay approximately the same (within 1% due to fees)
        // Fees cause slight deviation from perfect constant product
        assertApproxEqRel(finalProduct, initialProduct, 0.01e18, "Constant product should stay approximately constant");
    }
}
