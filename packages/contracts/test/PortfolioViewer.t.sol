// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {PortfolioViewer} from "../src/PortfolioViewer.sol";
import {CTFExchange} from "../src/CTFExchange.sol";

contract PortfolioViewerTest is Test {
    MockUSDC public usdc;
    MarketFactory public factory;
    ConditionalTokens public ctf;
    CTFExchange public exchange;
    PortfolioViewer public viewer;
    
    address public operator = address(1);
    address public feeRecipient = address(2);
    address public alice = address(3);
    address public bob = address(4);
    
    bytes32 public questionId1;
    bytes32 public questionId2;
    bytes32 public conditionId1;
    bytes32 public conditionId2;
    
    function setUp() public {
        usdc = new MockUSDC();
        factory = new MarketFactory(usdc, operator, feeRecipient, address(this));
        
        ctf = ConditionalTokens(factory.getCTF());
        exchange = CTFExchange(factory.getExchange());
        viewer = new PortfolioViewer(ctf, factory);
        
        // Create test markets
        questionId1 = factory.createMarket(
            "Will ETH reach $10k?",
            "Crypto",
            address(this),
            block.timestamp + 365 days,
            false
        );
        
        questionId2 = factory.createMarket(
            "Will BTC reach $100k?",
            "Crypto",
            address(this),
            block.timestamp + 365 days,
            false
        );
        
        MarketFactory.Market memory market1 = factory.getMarket(questionId1);
        MarketFactory.Market memory market2 = factory.getMarket(questionId2);
        conditionId1 = market1.conditionId;
        conditionId2 = market2.conditionId;
        
        // Setup users with USDC and positions
        usdc.mint(alice, 10000e6);
        usdc.mint(bob, 10000e6);
        
        // Alice gets positions in market 1
        vm.startPrank(alice);
        usdc.approve(address(ctf), 5000e6);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        ctf.splitPosition(usdc, bytes32(0), conditionId1, partition, 5000e6);
        vm.stopPrank();
        
        // Bob gets positions in both markets
        vm.startPrank(bob);
        usdc.approve(address(ctf), 10000e6);
        ctf.splitPosition(usdc, bytes32(0), conditionId1, partition, 3000e6);
        ctf.splitPosition(usdc, bytes32(0), conditionId2, partition, 4000e6);
        vm.stopPrank();
    }
    
    function testGetUserPosition() public {
        PortfolioViewer.Position memory position = viewer.getUserPosition(alice, questionId1);
        
        assertEq(position.questionId, questionId1, "Wrong question ID");
        assertEq(position.conditionId, conditionId1, "Wrong condition ID");
        assertEq(position.yesBalance, 5000e6, "Wrong YES balance");
        assertEq(position.noBalance, 5000e6, "Wrong NO balance");
        assertFalse(position.isResolved, "Should not be resolved");
    }
    
    function testGetUserPortfolio() public {
        PortfolioViewer.UserSummary memory portfolio = viewer.getUserPortfolio(bob);
        
        assertEq(portfolio.totalPositions, 2, "Wrong position count"); // 2 markets with positions
        assertEq(portfolio.activeMarkets, 2, "Wrong active market count");
        assertEq(portfolio.resolvedMarkets, 0, "Wrong resolved market count");
        assertTrue(portfolio.positions.length > 0, "Should have positions");
    }
    
    function testBatchGetPositions() public {
        bytes32[] memory questionIds = new bytes32[](2);
        questionIds[0] = questionId1;
        questionIds[1] = questionId2;
        
        PortfolioViewer.Position[] memory positions = viewer.batchGetPositions(alice, questionIds);
        
        assertEq(positions.length, 2, "Wrong array length");
        assertEq(positions[0].yesBalance, 5000e6, "Wrong alice market1 YES balance");
        assertEq(positions[0].noBalance, 5000e6, "Wrong alice market1 NO balance");
        assertEq(positions[1].yesBalance, 0, "Alice should have no market2 YES tokens");
        assertEq(positions[1].noBalance, 0, "Alice should have no market2 NO tokens");
    }
    
    function testEmptyPortfolio() public {
        address nobody = address(0x999);
        
        PortfolioViewer.UserSummary memory portfolio = viewer.getUserPortfolio(nobody);
        
        assertEq(portfolio.totalPositions, 0, "Should have no positions");
        assertEq(portfolio.activeMarkets, 0, "Should have no active markets");
        assertEq(portfolio.resolvedMarkets, 0, "Should have no resolved markets");
    }
    
    function testMultipleConditions() public {
        PortfolioViewer.UserSummary memory alicePortfolio = viewer.getUserPortfolio(alice);
        PortfolioViewer.UserSummary memory bobPortfolio = viewer.getUserPortfolio(bob);
        
        // Alice only has positions in market 1
        assertEq(alicePortfolio.totalPositions, 1, "Alice should have 1 market with positions");
        
        // Bob has positions in both markets
        assertEq(bobPortfolio.totalPositions, 2, "Bob should have 2 markets with positions");
    }
    
    function testBatchGetPositionsEmptyArray() public {
        bytes32[] memory questionIds = new bytes32[](0);
        
        PortfolioViewer.Position[] memory positions = viewer.batchGetPositions(alice, questionIds);
        
        assertEq(positions.length, 0, "Should return empty array");
    }
    
    function testGetPositionValue() public {
        bytes32 yesCollectionId = ctf.getCollectionId(bytes32(0), conditionId1, 1);
        uint256 yesPositionId = ctf.getPositionId(usdc, yesCollectionId);
        
        uint256 balance = ctf.balanceOf(alice, yesPositionId);
        assertEq(balance, 5000e6, "Alice should have 5000 YES tokens");
        
        PortfolioViewer.Position memory position = viewer.getUserPosition(alice, questionId1);
        
        assertEq(position.yesBalance, balance, "Position YES balance should match");
    }
}
