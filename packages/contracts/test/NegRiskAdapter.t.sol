// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {NegRiskAdapter} from "../src/NegRiskAdapter.sol";

contract NegRiskAdapterTest is Test {
    MockUSDC public usdc;
    ConditionalTokens public ctf;
    NegRiskAdapter public adapter;
    
    address public oracle = address(1);
    address public alice = address(2);
    address public bob = address(3);
    
    bytes32 public questionId;
    bytes32 public conditionId;
    uint256 public yesPositionId;
    uint256 public noPositionId;
    
    function setUp() public {
        usdc = new MockUSDC();
        ctf = new ConditionalTokens();
        adapter = new NegRiskAdapter(ctf);
        
        // Setup users
        usdc.mint(alice, 10000e6);
        usdc.mint(bob, 10000e6);
    }
    
    function testCreateNegRiskMarket() public {
        questionId = keccak256("Will NOT happen?");
        
        conditionId = adapter.createNegRiskMarket(
            questionId,
            oracle,
            usdc
        );
        
        // Verify condition was created (oracle is first parameter in CTF)
        bytes32 expectedConditionId = ctf.getConditionId(oracle, questionId, 2);
        assertEq(conditionId, expectedConditionId, "Condition ID mismatch");
        
        // Verify market data
        NegRiskAdapter.NegRiskMarket memory market = adapter.getMarket(questionId);
        assertEq(market.questionId, questionId, "Question ID mismatch");
        assertEq(market.oracle, oracle, "Oracle mismatch");
        assertFalse(market.resolved, "Should not be resolved");
        assertTrue(market.isNegRisk, "Should be neg risk market");
    }
    
    function testSplitPosition() public {
        // Create market
        questionId = keccak256("Will NOT happen?");
        conditionId = adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        // Setup alice
        vm.startPrank(alice);
        usdc.approve(address(adapter), 1000e6);
        
        // Split position
        adapter.splitPosition(questionId, 1000e6);
        
        // Get position IDs
        (uint256 yId, uint256 nId) = adapter.getPositionIds(questionId);
        yesPositionId = yId;
        noPositionId = nId;
        
        // Verify balances
        assertEq(ctf.balanceOf(alice, yesPositionId), 1000e6, "Wrong YES balance");
        assertEq(ctf.balanceOf(alice, noPositionId), 1000e6, "Wrong NO balance");
        vm.stopPrank();
    }
    
    function testMergePositions() public {
        // Create and split
        questionId = keccak256("Will NOT happen?");
        conditionId = adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        vm.startPrank(alice);
        usdc.approve(address(adapter), 1000e6);
        adapter.splitPosition(questionId, 1000e6);
        
        // Get position IDs
        (uint256 yId, uint256 nId) = adapter.getPositionIds(questionId);
        yesPositionId = yId;
        noPositionId = nId;
        
        // Approve adapter
        ctf.setApprovalForAll(address(adapter), true);
        
        uint256 usdcBefore = usdc.balanceOf(alice);
        
        // Merge positions
        adapter.mergePositions(questionId, 500e6);
        
        // Verify balances
        assertEq(ctf.balanceOf(alice, yesPositionId), 500e6, "Wrong YES balance after merge");
        assertEq(ctf.balanceOf(alice, noPositionId), 500e6, "Wrong NO balance after merge");
        assertEq(usdc.balanceOf(alice), usdcBefore + 500e6, "Wrong USDC balance after merge");
        vm.stopPrank();
    }
    
    function testCannotRedeemBeforeResolution() public {
        // Create and split
        questionId = keccak256("Will NOT happen?");
        conditionId = adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        vm.startPrank(alice);
        usdc.approve(address(adapter), 1000e6);
        adapter.splitPosition(questionId, 1000e6);
        
        // Calculate position IDs
        (uint256 yId, uint256 nId) = adapter.getPositionIds(questionId);
        yesPositionId = yId;
        noPositionId = nId;
        
        // Verify balances after split
        assertEq(ctf.balanceOf(alice, yesPositionId), 1000e6, "Wrong YES balance after split");
        assertEq(ctf.balanceOf(alice, noPositionId), 1000e6, "Wrong NO balance after split");
        
        // Try to redeem before resolution - should fail
        // Note: NegRiskAdapter doesn't have a public method to mark market as resolved
        // This test verifies the protection is in place
        vm.expectRevert("Not resolved");
        adapter.redeemPositions(questionId);
        vm.stopPrank();
    }
    
    function testGetMarketInfo() public {
        questionId = keccak256("Will NOT happen?");
        conditionId = adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        NegRiskAdapter.NegRiskMarket memory market = adapter.getMarket(questionId);
        
        assertEq(market.questionId, questionId);
        assertEq(market.oracle, oracle);
        assertFalse(market.resolved);
        assertTrue(market.isNegRisk);
    }
    
    function testGetPositionIds() public {
        questionId = keccak256("Will NOT happen?");
        adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        (uint256 yesId, uint256 noId) = adapter.getPositionIds(questionId);
        
        assertTrue(yesId > 0, "YES position ID should be set");
        assertTrue(noId > 0, "NO position ID should be set");
        assertTrue(yesId != noId, "Position IDs should be different");
    }
    
    function testIsNegRisk() public {
        questionId = keccak256("Will NOT happen?");
        conditionId = adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        assertTrue(adapter.isNegRisk(conditionId), "Should be neg risk market");
    }
    
    function testCannotSplitZeroAmount() public {
        questionId = keccak256("Will NOT happen?");
        conditionId = adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        vm.startPrank(alice);
        usdc.approve(address(adapter), 1000e6);
        
        vm.expectRevert();
        adapter.splitPosition(questionId, 0);
        vm.stopPrank();
    }
    
    function testCannotMergeZeroAmount() public {
        questionId = keccak256("Will NOT happen?");
        conditionId = adapter.createNegRiskMarket(questionId, oracle, usdc);
        
        vm.startPrank(alice);
        usdc.approve(address(adapter), 1000e6);
        adapter.splitPosition(questionId, 1000e6);
        
        ctf.setApprovalForAll(address(adapter), true);
        
        vm.expectRevert();
        adapter.mergePositions(questionId, 0);
        vm.stopPrank();
    }
}
