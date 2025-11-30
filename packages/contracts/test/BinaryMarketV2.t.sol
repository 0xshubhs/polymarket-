// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {BinaryMarketV2} from "../src/BinaryMarketV2.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {ProtocolConfig} from "../src/ProtocolConfig.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract BinaryMarketV2Test is Test {
    ConditionalTokens public conditionalTokens;
    MockUSDC public usdc;
    MarketFactory public factory;
    BinaryMarketV2 public market;
    
    address public oracle = address(0x1);
    address public trader = address(0x2);
    address public lp = address(0x3);
    address public treasury = address(0x4);
    
    string public constant QUESTION = "Will BTC reach $100k?";
    string public constant DESCRIPTION = "Bitcoin must reach $100,000 on Coinbase by Dec 31, 2025";
    string public constant CATEGORY = "Crypto";
    string[] public tags;
    
    function setUp() public {
        usdc = new MockUSDC();
        factory = new MarketFactory(usdc, treasury);
        conditionalTokens = factory.conditionalTokens();
        
        // Setup tags
        tags = new string[](2);
        tags[0] = "Bitcoin";
        tags[1] = "Price";
        
        // Transfer admin role from factory to test contract
        ProtocolConfig config = factory.protocolConfig();
        vm.prank(address(factory));
        config.transferAdmin(address(this));
        
        // Approve oracle and grant creator role
        config.setOracleApproval(oracle, true);
        config.grantRole(config.MARKET_CREATOR_ROLE(), address(this));
        
        // Create V2 market
        address marketAddr = factory.createMarketV2(
            oracle,
            QUESTION,
            DESCRIPTION,
            CATEGORY,
            tags,
            block.timestamp + 30 days
        );
        market = BinaryMarketV2(marketAddr);
        
        // Fund accounts
        usdc.transfer(trader, 10000 * 10**6);
        usdc.transfer(lp, 100000 * 10**6);
        
        vm.prank(trader);
        usdc.approve(address(market), type(uint256).max);
        
        vm.prank(lp);
        usdc.approve(address(market), type(uint256).max);
    }
    
    function testMetadata() public view {
        (
            string memory question,
            string memory description,
            string memory category,
            string[] memory _tags,
            ,
            uint256 createdAt,
            uint256 endTime
        ) = market.getMetadata();
        
        assertEq(question, QUESTION);
        assertEq(description, DESCRIPTION);
        assertEq(category, CATEGORY);
        assertEq(_tags.length, 2);
        assertEq(_tags[0], "Bitcoin");
        assertEq(_tags[1], "Price");
        assertTrue(createdAt > 0);
        assertTrue(endTime > block.timestamp);
    }
    
    function testAddLiquidityTracksUniqueTraders() public {
        vm.prank(lp);
        market.addLiquidity(1000 * 10**6);
        
        (,,,uint256 uniqueTraders,,,) = market.getStats();
        assertEq(uniqueTraders, 1);
    }
    
    function testTradeUpdatesVolume() public {
        // Add liquidity first
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        // Make a trade
        vm.prank(trader);
        market.buy(true, 1000 * 10**6, 0);
        
        (uint256 totalVolume, uint256 volume24h,,,,,) = market.getStats();
        
        assertEq(totalVolume, 1000 * 10**6);
        assertEq(volume24h, 1000 * 10**6);
    }
    
    function testVolumeResetsAfter24h() public {
        // Add liquidity
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        // Trade 1
        vm.prank(trader);
        market.buy(true, 1000 * 10**6, 0);
        
        (uint256 totalVolume1, uint256 volume24h1,,,,,) = market.getStats();
        assertEq(volume24h1, 1000 * 10**6);
        
        // Warp 25 hours
        vm.warp(block.timestamp + 25 hours);
        
        // Trade 2
        vm.prank(trader);
        market.buy(false, 500 * 10**6, 0);
        
        (uint256 totalVolume2, uint256 volume24h2,,,,,) = market.getStats();
        
        assertEq(totalVolume2, 1500 * 10**6); // Total keeps growing
        assertEq(volume24h2, 500 * 10**6); // 24h resets
    }
    
    function testTradeCountIncreases() public {
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        // Make 3 trades
        vm.startPrank(trader);
        market.buy(true, 100 * 10**6, 0);
        market.buy(false, 100 * 10**6, 0);
        market.buy(true, 100 * 10**6, 0);
        vm.stopPrank();
        
        (,, uint256 tradeCount,,,,) = market.getStats();
        assertEq(tradeCount, 3);
    }
    
    function testUniqueTradersCounted() public {
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        address trader2 = address(0x5);
        usdc.transfer(trader2, 10000 * 10**6);
        vm.prank(trader2);
        usdc.approve(address(market), type(uint256).max);
        
        // Both traders trade
        vm.prank(trader);
        market.buy(true, 100 * 10**6, 0);
        
        vm.prank(trader2);
        market.buy(false, 100 * 10**6, 0);
        
        // Trader 1 trades again
        vm.prank(trader);
        market.buy(true, 100 * 10**6, 0);
        
        (,,, uint256 uniqueTraders,,,) = market.getStats();
        assertEq(uniqueTraders, 3); // lp + trader + trader2
    }
    
    function testPriceHistorySnapshot() public {
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        // Initial snapshot should exist from liquidity add
        BinaryMarketV2.PriceSnapshot[] memory history = market.getPriceHistory();
        uint256 initialLength = history.length;
        
        // Warp 1 hour and trade to trigger snapshot
        vm.warp(block.timestamp + 1 hours);
        vm.prank(trader);
        market.buy(true, 1000 * 10**6, 0);
        
        history = market.getPriceHistory();
        assertTrue(history.length > initialLength);
    }
    
    function testPriceHistoryMaxLength() public {
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        // Create 30 snapshots (more than MAX_PRICE_HISTORY = 24)
        for (uint256 i = 0; i < 30; i++) {
            vm.warp(block.timestamp + 1 hours);
            vm.prank(trader);
            market.buy(true, 100 * 10**6, 0);
        }
        
        BinaryMarketV2.PriceSnapshot[] memory history = market.getPriceHistory();
        assertEq(history.length, 24); // Should cap at MAX_PRICE_HISTORY
    }
    
    function testUpdateMetadata() public {
        string memory newDescription = "Updated description";
        string memory newImageUrl = "ipfs://new-image";
        
        vm.prank(oracle);
        market.updateMetadata(newDescription, newImageUrl);
        
        (,string memory description,,,,,) = market.getMetadata();
        assertEq(description, newDescription);
    }
    
    function testOnlyOracleCanUpdateMetadata() public {
        vm.prank(trader);
        vm.expectRevert("Only oracle");
        market.updateMetadata("New desc", "New image");
    }
    
    function testGetStatsReturnsCorrectValues() public {
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        vm.prank(trader);
        market.buy(true, 1000 * 10**6, 0);
        
        (
            uint256 totalVolume,
            uint256 volume24h,
            uint256 tradeCount,
            uint256 uniqueTraders,
            uint256 totalLiquidity,
            uint256 yesPrice,
            uint256 noPrice
        ) = market.getStats();
        
        assertTrue(totalVolume > 0);
        assertTrue(volume24h > 0);
        assertTrue(tradeCount > 0);
        assertTrue(uniqueTraders > 0);
        assertTrue(totalLiquidity > 0);
        assertTrue(yesPrice > 0);
        assertTrue(noPrice > 0);
        // Allow 1 basis point tolerance for rounding
        uint256 sum = yesPrice + noPrice;
        assertTrue(sum >= 9999 && sum <= 10001, "Prices should sum to ~100%");
    }
    
    function testFuzzBuyWithMetadata(uint256 amount) public {
        amount = bound(amount, 100 * 10**6, 5000 * 10**6);
        
        vm.prank(lp);
        market.addLiquidity(10000 * 10**6);
        
        vm.prank(trader);
        market.buy(true, amount, 0);
        
        (uint256 totalVolume,,,,,,) = market.getStats();
        assertEq(totalVolume, amount);
    }
}
