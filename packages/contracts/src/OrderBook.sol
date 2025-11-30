// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OrderBook
/// @notice On-chain order book data structure for tracking limit orders
/// @dev This is supplementary to the CTFExchange - stores order metadata
library OrderBook {
    
    struct Order {
        address maker;
        uint256 price;          // Price per token (in collateral)
        uint256 size;           // Total size
        uint256 filled;         // Amount filled
        uint256 timestamp;      // When order was placed
        bool isActive;
    }

    struct Book {
        mapping(bytes32 => Order) orders;
        bytes32[] orderIds;
        uint256 totalVolume;
    }

    /// @notice Add order to book
    function addOrder(
        Book storage self,
        bytes32 orderId,
        address maker,
        uint256 price,
        uint256 size
    ) internal {
        require(!self.orders[orderId].isActive, "Order exists");
        
        self.orders[orderId] = Order({
            maker: maker,
            price: price,
            size: size,
            filled: 0,
            timestamp: block.timestamp,
            isActive: true
        });
        
        self.orderIds.push(orderId);
        self.totalVolume += size;
    }

    /// @notice Fill order partially or fully
    function fillOrder(
        Book storage self,
        bytes32 orderId,
        uint256 amount
    ) internal returns (uint256 filled) {
        Order storage order = self.orders[orderId];
        require(order.isActive, "Order not active");
        
        uint256 remaining = order.size - order.filled;
        filled = amount > remaining ? remaining : amount;
        
        order.filled += filled;
        
        if (order.filled >= order.size) {
            order.isActive = false;
        }
        
        return filled;
    }

    /// @notice Cancel an order
    function cancelOrder(Book storage self, bytes32 orderId) internal {
        Order storage order = self.orders[orderId];
        require(order.isActive, "Order not active");
        
        uint256 remaining = order.size - order.filled;
        self.totalVolume -= remaining;
        order.isActive = false;
    }

    /// @notice Get order details
    function getOrder(Book storage self, bytes32 orderId) 
        internal 
        view 
        returns (Order memory) 
    {
        return self.orders[orderId];
    }

    /// @notice Check if order is active
    function isActive(Book storage self, bytes32 orderId) 
        internal 
        view 
        returns (bool) 
    {
        return self.orders[orderId].isActive;
    }

    /// @notice Get remaining size
    function getRemaining(Book storage self, bytes32 orderId) 
        internal 
        view 
        returns (uint256) 
    {
        Order storage order = self.orders[orderId];
        return order.size - order.filled;
    }
}

/// @title OrderBookManager
/// @notice Manages separate bid and ask order books for markets
contract OrderBookManager {
    using OrderBook for OrderBook.Book;

    struct MarketBooks {
        OrderBook.Book bids;    // Buy orders
        OrderBook.Book asks;    // Sell orders
        bool exists;
    }

    mapping(bytes32 => MarketBooks) private markets;
    
    event OrderAdded(bytes32 indexed marketId, bytes32 indexed orderId, bool isBid, uint256 price, uint256 size);
    event OrderFilled(bytes32 indexed marketId, bytes32 indexed orderId, uint256 amount);
    event OrderCancelled(bytes32 indexed marketId, bytes32 indexed orderId);

    /// @notice Initialize market books
    function initializeMarket(bytes32 marketId) external {
        require(!markets[marketId].exists, "Market exists");
        markets[marketId].exists = true;
    }

    /// @notice Add a bid (buy order)
    function addBid(
        bytes32 marketId,
        bytes32 orderId,
        address maker,
        uint256 price,
        uint256 size
    ) external {
        require(markets[marketId].exists, "Market not found");
        markets[marketId].bids.addOrder(orderId, maker, price, size);
        emit OrderAdded(marketId, orderId, true, price, size);
    }

    /// @notice Add an ask (sell order)
    function addAsk(
        bytes32 marketId,
        bytes32 orderId,
        address maker,
        uint256 price,
        uint256 size
    ) external {
        require(markets[marketId].exists, "Market not found");
        markets[marketId].asks.addOrder(orderId, maker, price, size);
        emit OrderAdded(marketId, orderId, false, price, size);
    }

    /// @notice Fill a bid order
    function fillBid(bytes32 marketId, bytes32 orderId, uint256 amount) 
        external 
        returns (uint256) 
    {
        uint256 filled = markets[marketId].bids.fillOrder(orderId, amount);
        emit OrderFilled(marketId, orderId, filled);
        return filled;
    }

    /// @notice Fill an ask order
    function fillAsk(bytes32 marketId, bytes32 orderId, uint256 amount) 
        external 
        returns (uint256) 
    {
        uint256 filled = markets[marketId].asks.fillOrder(orderId, amount);
        emit OrderFilled(marketId, orderId, filled);
        return filled;
    }

    /// @notice Cancel a bid order
    function cancelBid(bytes32 marketId, bytes32 orderId) external {
        markets[marketId].bids.cancelOrder(orderId);
        emit OrderCancelled(marketId, orderId);
    }

    /// @notice Cancel an ask order
    function cancelAsk(bytes32 marketId, bytes32 orderId) external {
        markets[marketId].asks.cancelOrder(orderId);
        emit OrderCancelled(marketId, orderId);
    }

    /// @notice Get bid order
    function getBid(bytes32 marketId, bytes32 orderId) 
        external 
        view 
        returns (OrderBook.Order memory) 
    {
        return markets[marketId].bids.getOrder(orderId);
    }

    /// @notice Get ask order
    function getAsk(bytes32 marketId, bytes32 orderId) 
        external 
        view 
        returns (OrderBook.Order memory) 
    {
        return markets[marketId].asks.getOrder(orderId);
    }

    /// @notice Get total bid volume
    function getTotalBidVolume(bytes32 marketId) external view returns (uint256) {
        return markets[marketId].bids.totalVolume;
    }

    /// @notice Get total ask volume
    function getTotalAskVolume(bytes32 marketId) external view returns (uint256) {
        return markets[marketId].asks.totalVolume;
    }
}
