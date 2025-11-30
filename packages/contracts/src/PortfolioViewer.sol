// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";
import {MarketFactory} from "./MarketFactory.sol";

/// @title PortfolioViewer
/// @notice View contract for querying user positions across all markets (CLOB version)
/// @dev Optimized for the new CTF Exchange architecture
contract PortfolioViewer {
    struct Position {
        bytes32 questionId;
        bytes32 conditionId;
        string question;
        string category;
        uint256 yesPositionId;
        uint256 noPositionId;
        uint256 yesBalance;
        uint256 noBalance;
        bool isResolved;
        uint256 endTime;
    }
    
    struct UserSummary {
        uint256 totalPositions;
        uint256 activeMarkets;
        uint256 resolvedMarkets;
        Position[] positions;
    }
    
    ConditionalTokens public immutable conditionalTokens;
    MarketFactory public immutable marketFactory;
    
    constructor(ConditionalTokens _conditionalTokens, MarketFactory _marketFactory) {
        conditionalTokens = _conditionalTokens;
        marketFactory = _marketFactory;
    }
    
    /// @notice Get all positions for a user across all markets
    /// @param user Address of the user
    /// @return summary Complete portfolio summary
    function getUserPortfolio(address user) external view returns (UserSummary memory summary) {
        uint256 marketCount = marketFactory.marketCount();
        Position[] memory tempPositions = new Position[](marketCount);
        uint256 positionCount = 0;
        uint256 activeCount = 0;
        uint256 resolvedCount = 0;
        
        for (uint256 i = 0; i < marketCount; i++) {
            bytes32[] memory ids = marketFactory.getMarketIds(i, 1);
            if (ids.length == 0) continue;
            
            MarketFactory.Market memory market = marketFactory.getMarket(ids[0]);
            
            // Get position IDs
            bytes32 yesCollectionId = conditionalTokens.getCollectionId(bytes32(0), market.conditionId, 1);
            bytes32 noCollectionId = conditionalTokens.getCollectionId(bytes32(0), market.conditionId, 2);
            uint256 yesPositionId = conditionalTokens.getPositionId(marketFactory.collateralToken(), yesCollectionId);
            uint256 noPositionId = conditionalTokens.getPositionId(marketFactory.collateralToken(), noCollectionId);
            
            // Get balances
            uint256 yesBalance = conditionalTokens.balanceOf(user, yesPositionId);
            uint256 noBalance = conditionalTokens.balanceOf(user, noPositionId);
            
            // Skip if no position
            if (yesBalance == 0 && noBalance == 0) continue;
            
            tempPositions[positionCount] = Position({
                questionId: market.questionId,
                conditionId: market.conditionId,
                question: market.question,
                category: market.category,
                yesPositionId: yesPositionId,
                noPositionId: noPositionId,
                yesBalance: yesBalance,
                noBalance: noBalance,
                isResolved: market.resolved,
                endTime: market.endTime
            });
            
            positionCount++;
            
            if (market.resolved) {
                resolvedCount++;
            } else {
                activeCount++;
            }
        }
        
        // Trim array
        Position[] memory positions = new Position[](positionCount);
        for (uint256 i = 0; i < positionCount; i++) {
            positions[i] = tempPositions[i];
        }
        
        summary = UserSummary({
            totalPositions: positionCount,
            activeMarkets: activeCount,
            resolvedMarkets: resolvedCount,
            positions: positions
        });
    }
    
    /// @notice Get user position for a specific market
    /// @param user User address
    /// @param questionId Market question ID
    function getUserPosition(address user, bytes32 questionId) external view returns (Position memory) {
        MarketFactory.Market memory market = marketFactory.getMarket(questionId);
        require(market.createdAt > 0, "Market not found");
        
        // Get position IDs
        bytes32 yesCollectionId = conditionalTokens.getCollectionId(bytes32(0), market.conditionId, 1);
        bytes32 noCollectionId = conditionalTokens.getCollectionId(bytes32(0), market.conditionId, 2);
        uint256 yesPositionId = conditionalTokens.getPositionId(marketFactory.collateralToken(), yesCollectionId);
        uint256 noPositionId = conditionalTokens.getPositionId(marketFactory.collateralToken(), noCollectionId);
        
        return Position({
            questionId: market.questionId,
            conditionId: market.conditionId,
            question: market.question,
            category: market.category,
            yesPositionId: yesPositionId,
            noPositionId: noPositionId,
            yesBalance: conditionalTokens.balanceOf(user, yesPositionId),
            noBalance: conditionalTokens.balanceOf(user, noPositionId),
            isResolved: market.resolved,
            endTime: market.endTime
        });
    }
    
    /// @notice Batch get positions for multiple markets
    /// @param user User address
    /// @param questionIds Array of question IDs
    function batchGetPositions(address user, bytes32[] calldata questionIds) 
        external 
        view 
        returns (Position[] memory positions) 
    {
        positions = new Position[](questionIds.length);
        
        for (uint256 i = 0; i < questionIds.length; i++) {
            MarketFactory.Market memory market = marketFactory.getMarket(questionIds[i]);
            if (market.createdAt == 0) continue;
            
            bytes32 yesCollectionId = conditionalTokens.getCollectionId(bytes32(0), market.conditionId, 1);
            bytes32 noCollectionId = conditionalTokens.getCollectionId(bytes32(0), market.conditionId, 2);
            uint256 yesPositionId = conditionalTokens.getPositionId(marketFactory.collateralToken(), yesCollectionId);
            uint256 noPositionId = conditionalTokens.getPositionId(marketFactory.collateralToken(), noCollectionId);
            
            positions[i] = Position({
                questionId: market.questionId,
                conditionId: market.conditionId,
                question: market.question,
                category: market.category,
                yesPositionId: yesPositionId,
                noPositionId: noPositionId,
                yesBalance: conditionalTokens.balanceOf(user, yesPositionId),
                noBalance: conditionalTokens.balanceOf(user, noPositionId),
                isResolved: market.resolved,
                endTime: market.endTime
            });
        }
    }
}
