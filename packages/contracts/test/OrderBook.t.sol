// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract OrderBookTest is Test {
    OrderBookManager public manager;
    
    address public alice = address(1);
    address public bob = address(2);
    
    bytes32 public orderId1;
    bytes32 public orderId2;
    bytes32 public orderId3;
    
    function setUp() public {
        manager = new OrderBookManager();
        
        orderId1 = keccak256("order1");
        orderId2 = keccak256("order2");
        orderId3 = keccak256("order3");
    }
    
    function testAddOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        
        assertTrue(manager.orderExists(orderId1), "Order should exist");
        
        (address maker, uint256 price, uint256 size, uint256 filled, bool isActive) = manager.getOrderInfo(orderId1);
        assertEq(maker, alice, "Wrong maker");
        assertEq(price, 500000, "Wrong price");
        assertEq(size, 1000e6, "Wrong size");
        assertEq(filled, 0, "Should not be filled");
        assertTrue(isActive, "Should be active");
    }
    
    function testAddMultipleOrders() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        manager.addTestOrder(orderId2, bob, 600000, 2000e6);
        manager.addTestOrder(orderId3, alice, 550000, 1500e6);
        
        assertTrue(manager.orderExists(orderId1), "Order 1 should exist");
        assertTrue(manager.orderExists(orderId2), "Order 2 should exist");
        assertTrue(manager.orderExists(orderId3), "Order 3 should exist");
    }
    
    function testFillOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        
        uint256 filledAmount = manager.fillTestOrder(orderId1, 400e6);
        
        assertEq(filledAmount, 400e6, "Wrong filled amount");
        
        (, , , uint256 filled, bool isActive) = manager.getOrderInfo(orderId1);
        assertEq(filled, 400e6, "Order filled should be 400e6");
        assertTrue(isActive, "Order should still be active");
    }
    
    function testFullyFillOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        
        uint256 filledAmount = manager.fillTestOrder(orderId1, 1000e6);
        
        assertEq(filledAmount, 1000e6, "Should be fully filled");
        
        (, , , uint256 filled, bool isActive) = manager.getOrderInfo(orderId1);
        assertEq(filled, 1000e6, "Order should be fully filled");
        assertFalse(isActive, "Order should be inactive");
    }
    
    function testOverfillOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        
        uint256 filledAmount = manager.fillTestOrder(orderId1, 1500e6);
        
        assertEq(filledAmount, 1000e6, "Should only fill 1000e6");
        
        (, , , uint256 filled, bool isActive) = manager.getOrderInfo(orderId1);
        assertEq(filled, 1000e6, "Order should be fully filled");
        assertFalse(isActive, "Order should be inactive");
    }
    
    function testCancelOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        
        manager.cancelTestOrder(orderId1);
        
        (, , , , bool isActive) = manager.getOrderInfo(orderId1);
        assertFalse(isActive, "Order should be inactive");
    }
    
    function testPartialFills() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        
        manager.fillTestOrder(orderId1, 250e6);
        (, , , uint256 filled1, bool isActive1) = manager.getOrderInfo(orderId1);
        assertEq(filled1, 250e6, "First fill wrong");
        assertTrue(isActive1, "Should be active");
        
        manager.fillTestOrder(orderId1, 250e6);
        (, , , uint256 filled2, bool isActive2) = manager.getOrderInfo(orderId1);
        assertEq(filled2, 500e6, "Second fill wrong");
        assertTrue(isActive2, "Should be active");
        
        manager.fillTestOrder(orderId1, 500e6);
        (, , , uint256 filled3, bool isActive3) = manager.getOrderInfo(orderId1);
        assertEq(filled3, 1000e6, "Third fill wrong");
        assertFalse(isActive3, "Should be inactive");
    }
    
    function testGetTotalVolume() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        manager.addTestOrder(orderId2, bob, 600000, 2000e6);
        
        uint256 volume = manager.getTotalVolume();
        assertEq(volume, 3000e6, "Wrong total volume");
    }
    
    function testVolumeAfterCancel() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        manager.addTestOrder(orderId2, bob, 600000, 2000e6);
        
        assertEq(manager.getTotalVolume(), 3000e6, "Wrong initial volume");
        
        manager.cancelTestOrder(orderId1);
        
        uint256 volumeAfterCancel = manager.getTotalVolume();
        assertEq(volumeAfterCancel, 2000e6, "Wrong volume after cancel");
    }
    
    function testCannotAddDuplicateOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        
        vm.expectRevert("Order exists");
        manager.addTestOrder(orderId1, bob, 600000, 2000e6);
    }
    
    function testCannotFillInactiveOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        manager.cancelTestOrder(orderId1);
        
        vm.expectRevert("Order not active");
        manager.fillTestOrder(orderId1, 100e6);
    }
    
    function testCannotCancelInactiveOrder() public {
        manager.addTestOrder(orderId1, alice, 500000, 1000e6);
        manager.fillTestOrder(orderId1, 1000e6);
        
        vm.expectRevert("Order not active");
        manager.cancelTestOrder(orderId1);
    }
}

// Helper contract for testing OrderBook library
contract OrderBookManager {
    using OrderBook for OrderBook.Book;
    
    OrderBook.Book private book;
    
    function addTestOrder(
        bytes32 orderId,
        address maker,
        uint256 price,
        uint256 size
    ) external {
        book.addOrder(orderId, maker, price, size);
    }
    
    function fillTestOrder(bytes32 orderId, uint256 fillAmount) external returns (uint256) {
        return book.fillOrder(orderId, fillAmount);
    }
    
    function cancelTestOrder(bytes32 orderId) external {
        book.cancelOrder(orderId);
    }
    
    function getOrderInfo(bytes32 orderId) external view returns (
        address maker,
        uint256 price,
        uint256 size,
        uint256 filled,
        bool isActive
    ) {
        OrderBook.Order memory order = book.getOrder(orderId);
        return (order.maker, order.price, order.size, order.filled, order.isActive);
    }
    
    function orderExists(bytes32 orderId) external view returns (bool) {
        return book.isActive(orderId);
    }
    
    function getTotalVolume() external view returns (uint256) {
        return book.totalVolume;
    }
}
