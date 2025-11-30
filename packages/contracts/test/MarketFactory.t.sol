// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";

contract MarketFactoryTest is Test {
    MockUSDC public usdc;
    MarketFactory public factory;
    ConditionalTokens public ctf;
    
    address public operator = address(1);
    address public feeRecipient = address(2);
    address public treasury = address(3);
    
    function setUp() public {
        usdc = new MockUSDC();
        factory = new MarketFactory(usdc, operator, feeRecipient, treasury);
        ctf = ConditionalTokens(factory.getCTF());
    }
    
    function testCreateMarket() public {
        bytes32 questionId = factory.createMarket(
            "Will ETH reach $10k?",
            "Crypto",
            address(this),
            block.timestamp + 365 days,
            false
        );
        
        MarketFactory.Market memory market = factory.getMarket(questionId);
        assertEq(market.question, "Will ETH reach $10k?");
        assertEq(market.category, "Crypto");
        assertEq(market.resolver, address(this));
        assertFalse(market.isNegRisk);
        assertFalse(market.resolved);
    }
    
    function testMarketCount() public {
        uint256 countBefore = factory.marketCount();
        
        factory.createMarket(
            "Question 1",
            "Category",
            address(this),
            block.timestamp + 100 days,
            false
        );
        
        assertEq(factory.marketCount(), countBefore + 1);
    }
    
    function testResolveMarket() public {
        bytes32 questionId = factory.createMarket(
            "Will BTC reach $100k?",
            "Crypto",
            address(this),
            block.timestamp + 365 days,
            false
        );
        
        // Resolve: YES wins
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1; // YES
        payouts[1] = 0; // NO
        
        factory.resolveMarket(questionId, payouts);
        
        MarketFactory.Market memory market = factory.getMarket(questionId);
        assertTrue(market.resolved);
    }
    
    function testCannotResolveUnauthorized() public {
        bytes32 questionId = factory.createMarket(
            "Test Question",
            "Test",
            address(this),
            block.timestamp + 365 days,
            false
        );
        
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        payouts[1] = 0;
        
        vm.prank(address(0x123));
        vm.expectRevert();
        factory.resolveMarket(questionId, payouts);
    }
    
    function testGetMarketIds() public {
        factory.createMarket("Q1", "C1", address(this), block.timestamp + 100 days, false);
        factory.createMarket("Q2", "C2", address(this), block.timestamp + 100 days, false);
        factory.createMarket("Q3", "C3", address(this), block.timestamp + 100 days, false);
        
        bytes32[] memory ids = factory.getMarketIds(0, 3);
        assertEq(ids.length, 3);
    }
    
    function testCreateNegRiskMarket() public {
        bytes32 questionId = factory.createMarket(
            "Will NOT happen by date?",
            "NegRisk",
            address(this),
            block.timestamp + 365 days,
            true // negRisk
        );
        
        MarketFactory.Market memory market = factory.getMarket(questionId);
        assertTrue(market.isNegRisk);
    }
}
