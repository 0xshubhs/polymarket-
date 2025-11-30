// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";
import {BinaryMarket} from "./BinaryMarket.sol";
import {MarketFactory} from "./MarketFactory.sol";

/// @title PortfolioViewer
/// @notice View contract for efficiently querying user positions across all markets
/// @dev Read-only contract with batch query capabilities for better UX
contract PortfolioViewer {
    struct Position {
        address market;
        string question;
        uint256 yesBalance;
        uint256 noBalance;
        uint256 yesValue; // Current USD value
        uint256 noValue;
        uint256 totalValue;
        uint256 yesPrice; // Current price in basis points (5000 = 50%)
        uint256 noPrice;
        bool isResolved;
        uint256 endTime;
    }
    
    struct MarketStats {
        address market;
        string question;
        uint256 yesReserve;
        uint256 noReserve;
        uint256 totalLiquidity;
        uint256 volume24h;
        uint256 yesPrice;
        uint256 noPrice;
        uint256 endTime;
        bool isResolved;
        address oracle;
    }
    
    struct UserSummary {
        uint256 totalPositions;
        uint256 totalValueUSD;
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
        uint256 totalValue = 0;
        uint256 activeCount = 0;
        uint256 resolvedCount = 0;
        
        for (uint256 i = 0; i < marketCount; i++) {
            Position memory pos = _getUserPosition(user, marketFactory.getMarket(i));
            
            // Skip if user has no position in this market
            if (pos.yesBalance == 0 && pos.noBalance == 0) continue;
            
            tempPositions[positionCount] = pos;
            positionCount++;
            totalValue += pos.totalValue;
            
            if (pos.isResolved) {
                resolvedCount++;
            } else {
                activeCount++;
            }
        }
        
        // Trim array to actual size
        Position[] memory positions = new Position[](positionCount);
        for (uint256 i = 0; i < positionCount; i++) {
            positions[i] = tempPositions[i];
        }
        
        summary = UserSummary({
            totalPositions: positionCount,
            totalValueUSD: totalValue,
            activeMarkets: activeCount,
            resolvedMarkets: resolvedCount,
            positions: positions
        });
    }
    
    /// @notice Internal helper to get user position for a single market
    function _getUserPosition(address user, address marketAddr) internal view returns (Position memory pos) {
        BinaryMarket market = BinaryMarket(marketAddr);
        
        uint256 yesBalance = conditionalTokens.balanceOf(user, market.yesPositionId());
        uint256 noBalance = conditionalTokens.balanceOf(user, market.noPositionId());
        
        uint256 yesPrice = market.getPrice(true);
        uint256 noPrice = market.getPrice(false);
        
        // Calculate USD values (prices are in basis points, balances in token decimals)
        uint256 yesValue = (yesBalance * yesPrice) / 10000;
        uint256 noValue = (noBalance * noPrice) / 10000;
        
        pos = Position({
            market: marketAddr,
            question: market.question(),
            yesBalance: yesBalance,
            noBalance: noBalance,
            yesValue: yesValue,
            noValue: noValue,
            totalValue: yesValue + noValue,
            yesPrice: yesPrice,
            noPrice: noPrice,
            isResolved: market.isResolved(),
            endTime: market.endTime()
        });
    }
    
    /// @notice Get detailed stats for a batch of markets
    /// @param marketAddresses Array of market addresses
    /// @return stats Array of market statistics
    function getMarketStats(address[] calldata marketAddresses) external view returns (MarketStats[] memory stats) {
        uint256 length = marketAddresses.length;
        stats = new MarketStats[](length);
        
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                BinaryMarket market = BinaryMarket(marketAddresses[i]);
                
                stats[i] = MarketStats({
                    market: marketAddresses[i],
                    question: market.question(),
                    yesReserve: market.yesReserve(),
                    noReserve: market.noReserve(),
                    totalLiquidity: market.totalLiquidity(),
                    volume24h: 0,
                    yesPrice: market.getPrice(true),
                    noPrice: market.getPrice(false),
                    endTime: market.endTime(),
                    isResolved: market.isResolved(),
                    oracle: market.oracle()
                });
            }
        }
        
        return stats;
    }
    
    /// @notice Get user liquidity positions across markets
    /// @param user Address of the user
    /// @param markets Array of market addresses to check
    /// @return Array of liquidity token balances
    function getUserLiquidity(
        address user, 
        address[] calldata markets
    ) external view returns (uint256[] memory) {
        uint256 length = markets.length;
        uint256[] memory liquidityBalances = new uint256[](length);
        
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                liquidityBalances[i] = BinaryMarket(markets[i]).liquidityBalance(user);
            }
        }
        return liquidityBalances;
    }
    
    /// @notice Batch check if user has any position in markets
    /// @param user Address to check
    /// @param markets Array of market addresses
    /// @return hasPosition Array of booleans indicating if user has position
    function batchCheckPositions(address user, address[] calldata markets) external view returns (bool[] memory hasPosition) {
        hasPosition = new bool[](markets.length);
        
        for (uint256 i = 0; i < markets.length; i++) {
            BinaryMarket market = BinaryMarket(markets[i]);
            uint256 yesBalance = conditionalTokens.balanceOf(user, market.yesPositionId());
            uint256 noBalance = conditionalTokens.balanceOf(user, market.noPositionId());
            uint256 liquidityBalance = market.liquidityBalance(user);
            
            hasPosition[i] = (yesBalance > 0 || noBalance > 0 || liquidityBalance > 0);
        }
    }
    
    /// @notice Get user's total claimable value from resolved markets
    /// @param user Address of the user
    /// @return totalClaimable Total USD value claimable
    /// @return claimableMarkets Array of markets with claimable positions
    function getClaimableValue(address user) external view returns (uint256 totalClaimable, address[] memory claimableMarkets) {
        uint256 marketCount = marketFactory.marketCount();
        address[] memory tempMarkets = new address[](marketCount);
        uint256 claimableCount = 0;
        
        for (uint256 i = 0; i < marketCount; i++) {
            address marketAddr = marketFactory.getMarket(i);
            BinaryMarket market = BinaryMarket(marketAddr);
            
            if (!market.isResolved()) continue;
            
            uint256 yesBalance = conditionalTokens.balanceOf(user, market.yesPositionId());
            uint256 noBalance = conditionalTokens.balanceOf(user, market.noPositionId());
            
            if (yesBalance > 0 || noBalance > 0) {
                // User has tokens in resolved market - can claim
                tempMarkets[claimableCount] = marketAddr;
                claimableCount++;
                
                // Estimate claimable value (simplified - actual would need payout info)
                totalClaimable += yesBalance + noBalance;
            }
        }
        
        // Trim array
        claimableMarkets = new address[](claimableCount);
        for (uint256 i = 0; i < claimableCount; i++) {
            claimableMarkets[i] = tempMarkets[i];
        }
    }
}
