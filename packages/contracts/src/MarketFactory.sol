// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BinaryMarket} from "./BinaryMarket.sol";
import {BinaryMarketV2} from "./BinaryMarketV2.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";
import {ProtocolConfig} from "./ProtocolConfig.sol";

/// @title MarketFactory
/// @notice Factory contract for creating and managing binary prediction markets
/// @dev Supports both V1 (simple) and V2 (advanced) market types
contract MarketFactory is Ownable {
    ConditionalTokens public immutable conditionalTokens;
    IERC20 public immutable collateralToken;
    ProtocolConfig public protocolConfig;
    
    address[] public allMarkets;
    mapping(address => bool) public isMarket;
    
    event MarketCreated(
        address indexed market,
        address indexed oracle,
        string question,
        uint256 endTime,
        uint256 indexed marketIndex
    );
    
    event MarketV2Created(
        address indexed market,
        address indexed oracle,
        string question,
        string category,
        uint256 endTime,
        uint256 indexed marketIndex
    );
    
    event ProtocolConfigUpdated(address indexed oldConfig, address indexed newConfig);
    
    constructor(IERC20 _collateralToken, address _treasury) Ownable(msg.sender) {
        collateralToken = _collateralToken;
        conditionalTokens = new ConditionalTokens();
        protocolConfig = new ProtocolConfig(_treasury);
    }
    
    /// @notice Create a new binary prediction market (V1 - simple)
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
    
    /// @notice Create a new advanced binary prediction market (V2 - with metadata and analytics)
    /// @param oracle Address that will resolve the market
    /// @param question The prediction question
    /// @param description Detailed market description
    /// @param category Market category (e.g., "Crypto", "Sports", "Politics")
    /// @param tags Array of tags for filtering
    /// @param endTime Timestamp when trading ends
    function createMarketV2(
        address oracle,
        string memory question,
        string memory description,
        string memory category,
        string[] memory tags,
        uint256 endTime
    ) external returns (address market) {
        // Check if caller has permission
        require(
            protocolConfig.canCreateMarket(msg.sender),
            "Not authorized to create markets"
        );
        
        // Validate with protocol config
        protocolConfig.validateMarketParams(oracle, endTime, question);
        
        string memory questionHash = string(abi.encodePacked(question, category));
        require(protocolConfig.registerMarket(questionHash), "Market exists");
        
        BinaryMarketV2 newMarket = new BinaryMarketV2(
            conditionalTokens,
            collateralToken,
            oracle,
            question,
            description,
            category,
            tags,
            endTime
        );
        
        market = address(newMarket);
        allMarkets.push(market);
        isMarket[market] = true;
        
        emit MarketV2Created(market, oracle, question, category, endTime, allMarkets.length - 1);
    }
    
    /// @notice Update protocol config (admin only)
    function setProtocolConfig(address _config) external onlyOwner {
        require(_config != address(0), "Invalid config");
        address old = address(protocolConfig);
        protocolConfig = ProtocolConfig(_config);
        emit ProtocolConfigUpdated(old, _config);
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