// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract MarketFactoryTest is Test {
    MarketFactory public factory;
    MockUSDC public usdc;
    
    address public oracle = address(0x1);
    
    function setUp() public {
        usdc = new MockUSDC();
        factory = new MarketFactory(usdc, address(this));
    }
    
    function testCreateMarket() public {
        string memory question = "Will BTC reach $100k?";
        uint256 endTime = block.timestamp + 30 days;
        
        address market = factory.createMarket(oracle, question, endTime);
        
        assertTrue(market != address(0), "Market should be created");
        assertTrue(factory.isMarket(market), "Market should be registered");
        assertEq(factory.marketCount(), 1, "Market count should be 1");
    }
    
    function testCreateMultipleMarkets() public {
        uint256 marketCount = 5;
        
        for (uint256 i = 0; i < marketCount; i++) {
            string memory question = string(abi.encodePacked("Question ", vm.toString(i)));
            uint256 endTime = block.timestamp + 30 days;
            
            factory.createMarket(oracle, question, endTime);
        }
        
        assertEq(factory.marketCount(), marketCount, "Market count mismatch");
    }
    
    function testGetMarket() public {
        string memory question = "Test market";
        uint256 endTime = block.timestamp + 30 days;
        
        address createdMarket = factory.createMarket(oracle, question, endTime);
        address retrievedMarket = factory.getMarket(0);
        
        assertEq(retrievedMarket, createdMarket, "Retrieved market should match created market");
    }
    
    function testGetMarkets() public {
        // Create multiple markets
        for (uint256 i = 0; i < 10; i++) {
            string memory question = string(abi.encodePacked("Question ", vm.toString(i)));
            factory.createMarket(oracle, question, block.timestamp + 30 days);
        }
        
        // Get markets in range
        address[] memory markets = factory.getMarkets(0, 5);
        
        assertEq(markets.length, 5, "Should return 5 markets");
    }
    
    function testCannotCreateMarketWithInvalidOracle() public {
        vm.expectRevert("Invalid oracle");
        factory.createMarket(address(0), "Question", block.timestamp + 30 days);
    }
    
    function testCannotCreateMarketWithPastEndTime() public {
        vm.expectRevert("Invalid end time");
        factory.createMarket(oracle, "Question", block.timestamp - 1);
    }
    
    function testCannotCreateMarketWithEmptyQuestion() public {
        vm.expectRevert("Empty question");
        factory.createMarket(oracle, "", block.timestamp + 30 days);
    }
    
    function testMarketHasCorrectParameters() public {
        string memory question = "Test question";
        uint256 endTime = block.timestamp + 30 days;
        
        address marketAddr = factory.createMarket(oracle, question, endTime);
        BinaryMarket market = BinaryMarket(marketAddr);
        
        assertEq(market.question(), question, "Question mismatch");
        assertEq(market.endTime(), endTime, "End time mismatch");
        assertEq(market.oracle(), oracle, "Oracle mismatch");
        assertEq(address(market.collateralToken()), address(usdc), "Collateral token mismatch");
    }
    
    function testConditionalTokensShared() public {
        // Create two markets
        address market1 = factory.createMarket(oracle, "Question 1", block.timestamp + 30 days);
        address market2 = factory.createMarket(oracle, "Question 2", block.timestamp + 30 days);
        
        // Both should use the same conditional tokens contract
        BinaryMarket m1 = BinaryMarket(market1);
        BinaryMarket m2 = BinaryMarket(market2);
        
        assertEq(
            address(m1.conditionalTokens()),
            address(m2.conditionalTokens()),
            "Should share conditional tokens"
        );
    }
}
