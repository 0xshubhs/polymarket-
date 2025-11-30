// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PortfolioViewer} from "../src/PortfolioViewer.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {ProtocolConfig} from "../src/ProtocolConfig.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract PortfolioViewerTest is Test {
    ConditionalTokens public conditionalTokens;
    MockUSDC public usdc;
    MarketFactory public factory;
    PortfolioViewer public viewer;
    
    address public oracle = address(0x1);
    address public user = address(0x2);
    address public treasury = address(0x3);
    
    function setUp() public {
        usdc = new MockUSDC();
        factory = new MarketFactory(usdc, treasury);
        conditionalTokens = factory.conditionalTokens();
        viewer = new PortfolioViewer(conditionalTokens, factory);
        
        // Transfer admin role from factory to test contract
        ProtocolConfig config = factory.protocolConfig();
        vm.prank(address(factory));
        config.transferAdmin(address(this));
        
        // Approve oracle and grant creator role
        config.setOracleApproval(oracle, true);
        config.grantRole(config.MARKET_CREATOR_ROLE(), address(this));
        
        // Create some markets
        factory.createMarket(oracle, "Market 1", block.timestamp + 30 days);
        factory.createMarket(oracle, "Market 2", block.timestamp + 60 days);
        factory.createMarket(oracle, "Market 3", block.timestamp + 90 days);
    }
    
    function testGetEmptyPortfolio() public view {
        PortfolioViewer.UserSummary memory summary = viewer.getUserPortfolio(user);
        
        assertEq(summary.totalPositions, 0);
        assertEq(summary.totalValueUSD, 0);
        assertEq(summary.activeMarkets, 0);
        assertEq(summary.resolvedMarkets, 0);
        assertEq(summary.positions.length, 0);
    }
    
    function testGetPortfolioWithPositions() public {
        // Fund user
        usdc.transfer(user, 10000 * 10**6);
        
        address market1 = factory.getMarket(0);
        BinaryMarket bm1 = BinaryMarket(market1);
        
        // User adds liquidity
        vm.startPrank(user);
        usdc.approve(market1, type(uint256).max);
        bm1.addLiquidity(1000 * 10**6);
        vm.stopPrank();
        
        PortfolioViewer.UserSummary memory summary = viewer.getUserPortfolio(user);
        
        assertTrue(summary.totalPositions >= 2, "Should have YES and NO positions");
        assertEq(summary.activeMarkets, 1);
        assertEq(summary.resolvedMarkets, 0);
        assertTrue(summary.positions.length >= 2, "Should have at least 2 positions");
        assertEq(summary.positions[0].market, market1);
    }
    
    function testGetMarketStats() public view {
        address[] memory markets = new address[](3);
        markets[0] = factory.getMarket(0);
        markets[1] = factory.getMarket(1);
        markets[2] = factory.getMarket(2);
        
        PortfolioViewer.MarketStats[] memory stats = viewer.getMarketStats(markets);
        
        assertEq(stats.length, 3);
        assertEq(stats[0].market, markets[0]);
        assertEq(stats[1].market, markets[1]);
        assertEq(stats[2].market, markets[2]);
    }
    
    function testBatchCheckPositions() public {
        // Fund user
        usdc.transfer(user, 10000 * 10**6);
        
        address market1 = factory.getMarket(0);
        BinaryMarket bm1 = BinaryMarket(market1);
        
        // User adds liquidity to market 1
        vm.startPrank(user);
        usdc.approve(market1, type(uint256).max);
        bm1.addLiquidity(1000 * 10**6);
        vm.stopPrank();
        
        address[] memory markets = new address[](3);
        markets[0] = factory.getMarket(0);
        markets[1] = factory.getMarket(1);
        markets[2] = factory.getMarket(2);
        
        bool[] memory hasPosition = viewer.batchCheckPositions(user, markets);
        
        assertTrue(hasPosition[0]); // Has position in market 1
        assertFalse(hasPosition[1]); // No position in market 2
        assertFalse(hasPosition[2]); // No position in market 3
    }
    
    function testGetUserLiquidity() public {
        // Fund user
        usdc.transfer(user, 10000 * 10**6);
        
        address market1 = factory.getMarket(0);
        address market2 = factory.getMarket(1);
        BinaryMarket bm1 = BinaryMarket(market1);
        BinaryMarket bm2 = BinaryMarket(market2);
        
        // User adds liquidity to both markets
        vm.startPrank(user);
        usdc.approve(market1, type(uint256).max);
        usdc.approve(market2, type(uint256).max);
        bm1.addLiquidity(1000 * 10**6);
        bm2.addLiquidity(500 * 10**6);
        vm.stopPrank();
        
        address[] memory markets = new address[](2);
        markets[0] = market1;
        markets[1] = market2;
        
        uint256[] memory liquidity = viewer.getUserLiquidity(user, markets);
        
        assertTrue(liquidity[0] > 0);
        assertTrue(liquidity[1] > 0);
        assertTrue(liquidity[0] > liquidity[1]); // More liquidity in market1
    }
    
    function testGetClaimableValue() public {
        // Fund user and create position
        usdc.transfer(user, 10000 * 10**6);
        
        address market1 = factory.getMarket(0);
        BinaryMarket bm1 = BinaryMarket(market1);
        
        vm.startPrank(user);
        usdc.approve(market1, type(uint256).max);
        bm1.addLiquidity(1000 * 10**6);
        vm.stopPrank();
        
        // Initially no claimable (market not resolved)
        (uint256 claimable, address[] memory markets) = viewer.getClaimableValue(user);
        assertEq(claimable, 0);
        assertEq(markets.length, 0);
        
        // Resolve market
        vm.warp(block.timestamp + 31 days);
        
        // Report payouts as oracle
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1; // YES wins
        payouts[1] = 0; // NO loses
        
        vm.prank(oracle);
        conditionalTokens.reportPayouts(bm1.questionId(), payouts);
        
        // Now there should be claimable value
        (claimable, markets) = viewer.getClaimableValue(user);
        assertTrue(claimable > 0);
        assertEq(markets.length, 1);
        assertEq(markets[0], market1);
    }
}
