// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {CTFExchange} from "../src/CTFExchange.sol";

/// @title Simple Bet Placement Test
/// @notice Demonstrates betting functionality on the exchange
contract SimpleBetTest is Test {
    MockUSDC public usdc;
    ConditionalTokens public ctf;
    CTFExchange public exchange;
    
    address public operator = address(1);
    address public alice;
    address public bob;
    
    uint256 public alicePrivateKey = 0xA11CE;
    uint256 public bobPrivateKey = 0xB0B;
    
    bytes32 public questionId;
    bytes32 public conditionId;
    uint256 public yesTokenId;
    uint256 public noTokenId;
    
    function setUp() public {
        // Deploy contracts
        usdc = new MockUSDC();
        ctf = new ConditionalTokens();
        exchange = new CTFExchange(ctf, usdc, operator, address(this));
        
        // Setup users
        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);
        
        usdc.mint(alice, 10000e6);
        usdc.mint(bob, 10000e6);
        
        // Create a market: "Will ETH reach $5000 in 2026?"
        questionId = keccak256("Will ETH reach $5000 in 2026?");
        address oracle = address(this);
        
        vm.prank(oracle);
        ctf.prepareCondition(questionId, oracle, 2);
        
        conditionId = ctf.getConditionId(oracle, questionId, 2);
        
        // Calculate token IDs
        bytes32 yesCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 1);
        bytes32 noCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 2);
        yesTokenId = ctf.getPositionId(usdc, yesCollectionId);
        noTokenId = ctf.getPositionId(usdc, noCollectionId);
        
        // Give alice and bob outcome tokens to trade
        vm.startPrank(alice);
        usdc.approve(address(ctf), type(uint256).max);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        ctf.splitPosition(usdc, bytes32(0), conditionId, partition, 5000e6);
        ctf.setApprovalForAll(address(exchange), true);
        vm.stopPrank();
        
        vm.startPrank(bob);
        usdc.approve(address(ctf), type(uint256).max);
        ctf.splitPosition(usdc, bytes32(0), conditionId, partition, 5000e6);
        ctf.setApprovalForAll(address(exchange), true);
        vm.stopPrank();
    }
    
    function testMarketSetup() public {
        // Verify market is set up correctly
        assertEq(ctf.balanceOf(alice, yesTokenId), 5000e6, "Alice should have 5000 YES tokens");
        assertEq(ctf.balanceOf(alice, noTokenId), 5000e6, "Alice should have 5000 NO tokens");
        assertEq(ctf.balanceOf(bob, yesTokenId), 5000e6, "Bob should have 5000 YES tokens");
        assertEq(ctf.balanceOf(bob, noTokenId), 5000e6, "Bob should have 5000 NO tokens");
    }
    
    function testUserHasTokensToTrade() public {
        assertTrue(ctf.balanceOf(alice, yesTokenId) > 0, "Alice has YES tokens");
        assertTrue(ctf.balanceOf(bob, noTokenId) > 0, "Bob has NO tokens");
    }
    
    function testExchangeCanReceiveApprovals() public {
        assertTrue(ctf.isApprovedForAll(alice, address(exchange)), "Alice approved exchange");
        assertTrue(ctf.isApprovedForAll(bob, address(exchange)), "Bob approved exchange");
    }
    
    function testNonceInitialization() public {
        assertEq(exchange.nonces(alice), 0, "Alice nonce starts at 0");
        assertEq(exchange.nonces(bob), 0, "Bob nonce starts at 0");
    }
    
    function testIncrementNonce() public {
        vm.prank(alice);
        exchange.incrementNonce();
        assertEq(exchange.nonces(alice), 1, "Nonce incremented");
    }
}
