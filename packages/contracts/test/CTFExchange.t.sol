// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {OptimisticOracle} from "../src/OptimisticOracle.sol";

contract CTFExchangeTest is Test {
    MockUSDC public usdc;
    MarketFactory public factory;
    ConditionalTokens public ctf;
    CTFExchange public exchange;
    OptimisticOracle public oracle;
    
    address public operator = address(1);
    address public feeRecipient = address(2);
    address public alice = address(3);
    address public bob = address(4);
    
    bytes32 public questionId;
    bytes32 public conditionId;
    uint256 public yesPositionId;
    uint256 public noPositionId;
    
    function setUp() public {
        // Deploy contracts
        usdc = new MockUSDC();
        factory = new MarketFactory(usdc, operator, feeRecipient, address(this));
        
        // Get deployed contracts
        ctf = ConditionalTokens(factory.getCTF());
        exchange = CTFExchange(factory.getExchange());
        oracle = OptimisticOracle(factory.getOracle());
        
        // Create a test market
        questionId = factory.createMarket(
            "Will ETH reach $10k?",
            "Crypto",
            address(this),
            block.timestamp + 365 days,
            false
        );
        
        MarketFactory.Market memory market = factory.getMarket(questionId);
        conditionId = market.conditionId;
        
        // Calculate position IDs
        bytes32 yesCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 1);
        bytes32 noCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 2);
        yesPositionId = ctf.getPositionId(usdc, yesCollectionId);
        noPositionId = ctf.getPositionId(usdc, noCollectionId);
        
        // Setup users with USDC
        usdc.mint(alice, 10000e6);
        usdc.mint(bob, 10000e6);
        
        // Setup users with outcome tokens
        vm.startPrank(alice);
        usdc.approve(address(ctf), 5000e6);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        ctf.splitPosition(usdc, bytes32(0), conditionId, partition, 5000e6);
        vm.stopPrank();
        
        vm.startPrank(bob);
        usdc.approve(address(ctf), 5000e6);
        ctf.splitPosition(usdc, bytes32(0), conditionId, partition, 5000e6);
        vm.stopPrank();
    }
    
    function testMatchOrders() public {
        // Alice wants to sell YES tokens
        // Bob wants to buy YES tokens
        
        vm.startPrank(alice);
        ctf.setApprovalForAll(address(exchange), true);
        vm.stopPrank();
        
        vm.startPrank(bob);
        usdc.approve(address(exchange), 1000e6);
        vm.stopPrank();
        
        // Create orders
        CTFExchange.Order memory aliceOrder = CTFExchange.Order({
            salt: keccak256("alice1"),
            maker: alice,
            signer: alice,
            taker: address(0),
            tokenId: yesPositionId,
            makerAmount: 1000e6,
            takerAmount: 500e6,
            expiration: block.timestamp + 1 days,
            nonce: 0,
            feeRateBps: 0,
            side: CTFExchange.Side.SELL,
            signatureType: CTFExchange.SignatureType.EOA
        });
        
        CTFExchange.Order memory bobOrder = CTFExchange.Order({
            salt: keccak256("bob1"),
            maker: bob,
            signer: bob,
            taker: address(0),
            tokenId: yesPositionId,
            makerAmount: 500e6,
            takerAmount: 1000e6,
            expiration: block.timestamp + 1 days,
            nonce: 0,
            feeRateBps: 20,
            side: CTFExchange.Side.BUY,
            signatureType: CTFExchange.SignatureType.EOA
        });
        
        // Sign orders (simplified - in production use EIP-712)
        bytes memory aliceSig = _signOrder(aliceOrder);
        bytes memory bobSig = _signOrder(bobOrder);
        
        uint256 aliceYesBefore = ctf.balanceOf(alice, yesPositionId);
        uint256 bobYesBefore = ctf.balanceOf(bob, yesPositionId);
        
        // Match orders
        vm.prank(operator);
        exchange.matchOrders(aliceOrder, bobOrder, aliceSig, bobSig, 1000e6);
        
        // Verify balances changed
        assertLt(ctf.balanceOf(alice, yesPositionId), aliceYesBefore, "Alice YES balance should decrease");
        assertGt(ctf.balanceOf(bob, yesPositionId), bobYesBefore, "Bob YES balance should increase");
    }
    
    function testCancelOrder() public {
        CTFExchange.Order memory order = CTFExchange.Order({
            salt: keccak256("cancel1"),
            maker: alice,
            signer: alice,
            taker: address(0),
            tokenId: yesPositionId,
            makerAmount: 1000e6,
            takerAmount: 500e6,
            expiration: block.timestamp + 1 days,
            nonce: 0,
            feeRateBps: 0,
            side: CTFExchange.Side.SELL,
            signatureType: CTFExchange.SignatureType.EOA
        });
        
        vm.prank(alice);
        exchange.cancelOrder(order);
        
        bytes32 orderHash = exchange.hashOrder(order);
        assertTrue(exchange.cancelled(orderHash), "Order should be cancelled");
    }
    
    function testIncrementNonce() public {
        uint256 nonceBefore = exchange.nonces(alice);
        
        vm.prank(alice);
        exchange.incrementNonce();
        
        assertEq(exchange.nonces(alice), nonceBefore + 1, "Nonce should increment");
    }
    
    function testFeeCollection() public {
        // Setup similar to testMatchOrders
        vm.prank(alice);
        ctf.setApprovalForAll(address(exchange), true);
        
        vm.prank(bob);
        usdc.approve(address(exchange), 1000e6);
        
        CTFExchange.Order memory sellOrder = CTFExchange.Order({
            salt: keccak256("sell1"),
            maker: alice,
            signer: alice,
            taker: address(0),
            tokenId: yesPositionId,
            makerAmount: 1000e6,
            takerAmount: 600e6,
            expiration: block.timestamp + 1 days,
            nonce: 0,
            feeRateBps: 0,
            side: CTFExchange.Side.SELL,
            signatureType: CTFExchange.SignatureType.EOA
        });
        
        CTFExchange.Order memory buyOrder = CTFExchange.Order({
            salt: keccak256("buy1"),
            maker: bob,
            signer: bob,
            taker: address(0),
            tokenId: yesPositionId,
            makerAmount: 600e6,
            takerAmount: 1000e6,
            expiration: block.timestamp + 1 days,
            nonce: 0,
            feeRateBps: 20,
            side: CTFExchange.Side.BUY,
            signatureType: CTFExchange.SignatureType.EOA
        });
        
        bytes memory sellSig = _signOrder(sellOrder);
        bytes memory buySig = _signOrder(buyOrder);
        
        uint256 feeRecipientBefore = usdc.balanceOf(feeRecipient);
        
        vm.prank(operator);
        exchange.matchOrders(sellOrder, buyOrder, sellSig, buySig, 1000e6);
        
        uint256 feeRecipientAfter = usdc.balanceOf(feeRecipient);
        assertGt(feeRecipientAfter, feeRecipientBefore, "Fees should be collected");
    }
    
    // Helper function (simplified signature)
    function _signOrder(CTFExchange.Order memory order) internal pure returns (bytes memory) {
        // In production, use proper EIP-712 signing
        // For testing, return dummy signature
        return abi.encodePacked(bytes32(0), bytes32(0), uint8(27));
    }
}
