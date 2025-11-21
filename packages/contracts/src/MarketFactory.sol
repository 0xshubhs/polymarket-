// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BinaryMarket} from "./BinaryMarket.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";

/// @title MarketFactory
/// @notice Factory contract for creating and managing binary prediction markets
contract MarketFactory is Ownable {
    ConditionalTokens public immutable conditionalTokens;
    IERC20 public immutable collateralToken;
    
    address[] public allMarkets;
    mapping(address => bool) public isMarket;
    
    event MarketCreated(
        address indexed market,
        address indexed oracle,
        string question,
        uint256 endTime,
        uint256 indexed marketIndex
    );
    
    constructor(IERC20 _collateralToken) Ownable(msg.sender) {
        collateralToken = _collateralToken;
        conditionalTokens = new ConditionalTokens();
    }
    
    /// @notice Create a new binary prediction market
    /// @param oracle Address that will resolve the market
    /// @param question The prediction question
    /// @param endTime Timestamp when trading ends
    function createMarket(
        address oracle,
        string memory question,
        uint256 endTime
    ) external returns (address market) {
        require(oracle != address(0), "Invalid oracle");
        require(endTime > block.timestamp, "Invalid end time");
        require(bytes(question).length > 0, "Empty question");
        
        BinaryMarket newMarket = new BinaryMarket(
            conditionalTokens,
            collateralToken,
            oracle,
            question,
            endTime
        );
        
        market = address(newMarket);
        allMarkets.push(market);
        isMarket[market] = true;
        
        emit MarketCreated(market, oracle, question, endTime, allMarkets.length - 1);
    }
    
    /// @notice Get total number of markets
    function marketCount() external view returns (uint256) {
        return allMarkets.length;
    }
    
    /// @notice Get market address by index
    function getMarket(uint256 index) external view returns (address) {
        require(index < allMarkets.length, "Index out of bounds");
        return allMarkets[index];
    }
    
    /// @notice Get all markets in a range
    function getMarkets(uint256 start, uint256 count) external view returns (address[] memory) {
        require(start < allMarkets.length, "Start out of bounds");
        
        uint256 end = start + count;
        if (end > allMarkets.length) {
            end = allMarkets.length;
        }
        
        address[] memory markets = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            markets[i - start] = allMarkets[i];
        }
        
        return markets;
    }
}