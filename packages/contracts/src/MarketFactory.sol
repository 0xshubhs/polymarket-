// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";
import {CTFExchange} from "./CTFExchange.sol";
import {OptimisticOracle} from "./OptimisticOracle.sol";
import {NegRiskAdapter} from "./NegRiskAdapter.sol";
import {ProtocolConfig} from "./ProtocolConfig.sol";

/// @title MarketFactory
/// @notice Factory contract for creating prediction markets using Polymarket architecture
/// @dev Creates markets using CTF + CTFExchange + OptimisticOracle (CLOB model, not AMM)
contract MarketFactory is Ownable {
    ConditionalTokens public immutable conditionalTokens;
    CTFExchange public immutable ctfExchange;
    OptimisticOracle public immutable optimisticOracle;
    NegRiskAdapter public immutable negRiskAdapter;
    IERC20 public immutable collateralToken;
    ProtocolConfig public protocolConfig;
    
    struct Market {
        bytes32 questionId;
        bytes32 conditionId;
        string question;
        string category;
        address resolver;
        uint256 endTime;
        uint256 createdAt;
        bool isNegRisk;
        bool resolved;
    }
    
    bytes32[] public allMarketIds;
    mapping(bytes32 => Market) public marketData;
    
    event MarketCreated(
        bytes32 indexed questionId,
        bytes32 indexed conditionId,
        address indexed resolver,
        string question,
        string category,
        uint256 endTime,
        bool isNegRisk
    );
    
    event MarketResolved(
        bytes32 indexed questionId,
        bytes32 indexed conditionId,
        uint256[] payouts
    );
    
    event ProtocolConfigUpdated(address indexed oldConfig, address indexed newConfig);
    
    constructor(
        IERC20 _collateralToken,
        address _operator,
        address _feeRecipient,
        address _treasury
    ) Ownable(msg.sender) {
        collateralToken = _collateralToken;
        conditionalTokens = new ConditionalTokens();
        ctfExchange = new CTFExchange(conditionalTokens, _collateralToken, _operator, _feeRecipient);
        optimisticOracle = new OptimisticOracle(_collateralToken, msg.sender);
        negRiskAdapter = new NegRiskAdapter(conditionalTokens);
        protocolConfig = new ProtocolConfig(_treasury);
        
        // Grant deployer all roles for convenience
        protocolConfig.grantRole(protocolConfig.MARKET_CREATOR_ROLE(), msg.sender);
    }
    
    /// @notice Create a new prediction market
    /// @param question The prediction question
    /// @param category Market category
    /// @param resolver Address that can resolve via oracle
    /// @param endTime When trading/market ends
    /// @param isNegRisk Whether this is a negative risk market
    function createMarket(
        string memory question,
        string memory category,
        address resolver,
        uint256 endTime,
        bool isNegRisk
    ) external returns (bytes32 questionId) {
        require(bytes(question).length > 0, "Empty question");
        require(endTime > block.timestamp, "Invalid end time");
        require(resolver != address(0), "Invalid resolver");
        
        // Check if caller has permission
        require(
            protocolConfig.canCreateMarket(msg.sender),
            "Not authorized to create markets"
        );
        
        // Generate unique question ID
        questionId = keccak256(
            abi.encodePacked(question, category, block.timestamp, msg.sender)
        );
        
        require(marketData[questionId].createdAt == 0, "Market exists");
        
        bytes32 conditionId;
        
        if (isNegRisk) {
            // Create via NegRiskAdapter
            conditionId = negRiskAdapter.createNegRiskMarket(
                questionId,
                resolver,
                collateralToken
            );
        } else {
            // Create standard market via CTF
            // MarketFactory is the oracle, so it can resolve markets
            conditionalTokens.prepareCondition(questionId, address(this), 2);
            conditionId = conditionalTokens.getConditionId(address(this), questionId, 2);
        }
        
        // Store market data
        marketData[questionId] = Market({
            questionId: questionId,
            conditionId: conditionId,
            question: question,
            category: category,
            resolver: resolver,
            endTime: endTime,
            createdAt: block.timestamp,
            isNegRisk: isNegRisk,
            resolved: false
        });
        
        allMarketIds.push(questionId);
        
        // Register with protocol config
        string memory questionHash = string(abi.encodePacked(question, category));
        protocolConfig.registerMarket(questionHash);
        
        emit MarketCreated(
            questionId,
            conditionId,
            resolver,
            question,
            category,
            endTime,
            isNegRisk
        );
    }
    
    /// @notice Resolve a market using optimistic oracle
    /// @param questionId Market to resolve
    /// @param payouts Payout array [yesAmount, noAmount]
    function resolveMarket(
        bytes32 questionId,
        uint256[] calldata payouts
    ) external {
        Market storage market = marketData[questionId];
        require(market.createdAt > 0, "Market not found");
        require(!market.resolved, "Already resolved");
        require(msg.sender == market.resolver, "Not resolver");
        require(payouts.length == 2, "Invalid payouts");
        
        // Report payouts to CTF
        // Note: reportPayouts will verify msg.sender matches the oracle used in prepareCondition
        conditionalTokens.reportPayouts(market.questionId, payouts);
        
        market.resolved = true;
        
        emit MarketResolved(questionId, market.conditionId, payouts);
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
        return allMarketIds.length;
    }
    
    /// @notice Get market by question ID
    function getMarket(bytes32 questionId) external view returns (Market memory) {
        return marketData[questionId];
    }
    
    /// @notice Get all market IDs in a range
    function getMarketIds(uint256 start, uint256 count) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        require(start < allMarketIds.length, "Start out of bounds");
        
        uint256 end = start + count;
        if (end > allMarketIds.length) {
            end = allMarketIds.length;
        }
        
        bytes32[] memory ids = new bytes32[](end - start);
        for (uint256 i = start; i < end; i++) {
            ids[i - start] = allMarketIds[i];
        }
        
        return ids;
    }
    
    /// @notice Get the CTF Exchange address
    function getExchange() external view returns (address) {
        return address(ctfExchange);
    }
    
    /// @notice Get the ConditionalTokens address
    function getCTF() external view returns (address) {
        return address(conditionalTokens);
    }
    
    /// @notice Get the OptimisticOracle address
    function getOracle() external view returns (address) {
        return address(optimisticOracle);
    }
}