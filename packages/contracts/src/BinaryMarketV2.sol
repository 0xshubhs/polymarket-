// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";

/// @title BinaryMarketV2
/// @notice Production-ready AMM for binary prediction markets with comprehensive analytics and metadata
/// @dev Advanced market implementation with volume tracking, categories, tags, and price history
contract BinaryMarketV2 is ReentrancyGuard, IERC1155Receiver {
    using SafeERC20 for IERC20;

    ConditionalTokens public immutable conditionalTokens;
    IERC20 public immutable collateralToken;
    
    bytes32 public immutable conditionId;
    bytes32 public immutable questionId;
    address public immutable oracle;
    
    uint256 public immutable yesPositionId;
    uint256 public immutable noPositionId;
    uint32 public immutable createdAt;
    
    string public question;
    string public description;
    string public category;
    string[] public tags;
    string public imageUrl;
    
    // Packed slot 1: timestamps and flags
    uint96 public endTime;
    uint96 public resolutionTime;
    uint16 public feeRate;
    uint32 public lastVolumeReset;
    bool public isResolved;
    
    // AMM state
    uint256 public yesReserve;
    uint256 public noReserve;
    uint256 public totalLiquidity;
    uint256 public accumulatedFees;
    mapping(address => uint256) public liquidityBalance;
    
    // Enhanced tracking
    uint256 public totalVolume;
    uint256 public volume24h;
    
    // Packed slot 2: counters
    uint128 public tradeCount;
    uint128 public uniqueTraders;
    
    // Constants
    uint256 public constant FEE_DENOMINATOR = 10000;
    mapping(address => bool) private hasTraded; // Track unique traders
    
    // Price history snapshots (last 24 hours)
    struct PriceSnapshot {
        uint256 timestamp;
        uint256 yesPrice;
        uint256 noPrice;
        uint256 yesReserve;
        uint256 noReserve;
    }
    PriceSnapshot[] public priceHistory;
    uint256 public constant MAX_PRICE_HISTORY = 24; // Store hourly snapshots
    uint256 public lastSnapshotTime;
    
    // Liquidity provider stats
    mapping(address => uint256) public lpFeesEarned; // Track fees earned by LPs
    
    event LiquidityAdded(address indexed provider, uint256 amount, uint256 liquidity, uint256 timestamp);
    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 liquidity, uint256 timestamp);
    event Trade(
        address indexed trader,
        bool buyYes,
        uint256 amountIn,
        uint256 amountOut,
        uint256 yesReserve,
        uint256 noReserve,
        uint256 yesPrice,
        uint256 noPrice,
        uint256 timestamp
    );
    event MarketResolved(uint256 yesPayoutNumerator, uint256 noPayoutNumerator, uint256 timestamp);
    event MetadataUpdated(string description, string category, string imageUrl);
    event TagsUpdated(string[] tags);
    event PriceSnapshotTaken(uint256 indexed timestamp, uint256 yesPrice, uint256 noPrice);
    
    constructor(
        ConditionalTokens _conditionalTokens,
        IERC20 _collateralToken,
        address _oracle,
        string memory _question,
        string memory _description,
        string memory _category,
        string[] memory _tags,
        uint256 _endTime
    ) {
        require(bytes(_question).length > 0, "Empty question");
        require(bytes(_category).length > 0, "Empty category");
        require(_endTime > block.timestamp, "Invalid end time");
        
        conditionalTokens = _conditionalTokens;
        collateralToken = _collateralToken;
        oracle = _oracle;
        question = _question;
        description = _description;
        category = _category;
        tags = _tags;
        endTime = uint96(_endTime);
        createdAt = uint32(block.timestamp);
        feeRate = 10; // 0.1% default
        lastVolumeReset = uint32(block.timestamp);
        lastSnapshotTime = block.timestamp;
        
        // Create unique question ID
        questionId = keccak256(abi.encodePacked(_question, block.timestamp, address(this)));
        
        // Prepare condition in ConditionalTokens
        conditionalTokens.prepareCondition(questionId, _oracle, 2);
        conditionId = conditionalTokens.getConditionId(_oracle, questionId, 2);
        
        // Calculate position IDs for YES (index 0) and NO (index 1)
        bytes32 parentCollectionId = bytes32(0);
        yesPositionId = conditionalTokens.getPositionId(
            _collateralToken,
            conditionalTokens.getCollectionId(parentCollectionId, conditionId, 0)
        );
        noPositionId = conditionalTokens.getPositionId(
            _collateralToken,
            conditionalTokens.getCollectionId(parentCollectionId, conditionId, 1)
        );
    }
    
    /// @notice Add liquidity to the market
    function addLiquidity(uint256 amount) external nonReentrant returns (uint256 liquidity) {
        require(amount > 0, "Amount must be positive");
        require(block.timestamp < endTime, "Market ended");
        
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        
        collateralToken.approve(address(conditionalTokens), amount);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 0; // YES
        partition[1] = 1; // NO
        
        conditionalTokens.splitPosition(
            collateralToken,
            bytes32(0),
            conditionId,
            partition,
            amount
        );
        
        if (totalLiquidity == 0) {
            liquidity = amount;
            yesReserve = amount;
            noReserve = amount;
        } else {
            liquidity = (amount * totalLiquidity) / (yesReserve + noReserve);
        }
        
        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;
        
        _trackUniqueTrader(msg.sender);
        _snapshotPrice();
        
        emit LiquidityAdded(msg.sender, amount, liquidity, block.timestamp);
    }
    
    /// @notice Buy outcome tokens
    function buy(bool buyYes, uint256 investmentAmount, uint256 minTokensOut) 
        external 
        nonReentrant 
        returns (uint256 tokensOut) 
    {
        require(investmentAmount > 0, "Invalid investment");
        require(block.timestamp < endTime, "Market ended");
        require(!isResolved, "Market resolved");
        
        collateralToken.safeTransferFrom(msg.sender, address(this), investmentAmount);
        
        collateralToken.approve(address(conditionalTokens), investmentAmount);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 0;
        partition[1] = 1;
        
        conditionalTokens.splitPosition(
            collateralToken,
            bytes32(0),
            conditionId,
            partition,
            investmentAmount
        );
        
        uint256 fee = (investmentAmount * feeRate) / FEE_DENOMINATOR;
        uint256 amountAfterFee = investmentAmount - fee;
        accumulatedFees += fee;
        
        uint256 sellReserve = buyYes ? noReserve : yesReserve;
        uint256 buyReserve = buyYes ? yesReserve : noReserve;
        
        uint256 k = yesReserve * noReserve;
        uint256 newSellReserve = sellReserve + amountAfterFee;
        uint256 newBuyReserve = k / newSellReserve;
        
        tokensOut = buyReserve - newBuyReserve;
        require(tokensOut >= minTokensOut, "Slippage exceeded");
        
        if (buyYes) {
            yesReserve = newBuyReserve;
            noReserve = newSellReserve;
            conditionalTokens.safeTransferFrom(
                address(this),
                msg.sender,
                yesPositionId,
                tokensOut,
                ""
            );
        } else {
            noReserve = newBuyReserve;
            yesReserve = newSellReserve;
            conditionalTokens.safeTransferFrom(
                address(this),
                msg.sender,
                noPositionId,
                tokensOut,
                ""
            );
        }
        
        _updateVolume(investmentAmount);
        _trackUniqueTrader(msg.sender);
        _snapshotPrice();
        tradeCount++;
        
        emit Trade(
            msg.sender,
            buyYes,
            investmentAmount,
            tokensOut,
            yesReserve,
            noReserve,
            getPrice(true),
            getPrice(false),
            block.timestamp
        );
    }
    
    /// @notice Get current price for an outcome (in basis points, 10000 = 100%)
    function getPrice(bool forYes) public view returns (uint256) {
        if (yesReserve == 0 || noReserve == 0) return 5000; // 50% default
        
        uint256 total = yesReserve + noReserve;
        if (forYes) {
            return (noReserve * 10000) / total;
        } else {
            return (yesReserve * 10000) / total;
        }
    }
    
    /// @notice Get market statistics
    function getStats() external view returns (
        uint256 _totalVolume,
        uint256 _volume24h,
        uint256 _tradeCount,
        uint256 _uniqueTraders,
        uint256 _totalLiquidity,
        uint256 _yesPrice,
        uint256 _noPrice
    ) {
        return (
            totalVolume,
            volume24h,
            tradeCount,
            uniqueTraders,
            totalLiquidity,
            getPrice(true),
            getPrice(false)
        );
    }
    
    /// @notice Get price history snapshots
    function getPriceHistory() external view returns (PriceSnapshot[] memory) {
        return priceHistory;
    }
    
    /// @notice Get market metadata
    function getMetadata() external view returns (
        string memory _question,
        string memory _description,
        string memory _category,
        string[] memory _tags,
        string memory _imageUrl,
        uint256 _createdAt,
        uint256 _endTime
    ) {
        return (question, description, category, tags, imageUrl, createdAt, endTime);
    }
    
    /// @notice Update metadata (only oracle can update)
    function updateMetadata(
        string calldata _description,
        string calldata _imageUrl
    ) external {
        require(msg.sender == oracle, "Only oracle");
        description = _description;
        imageUrl = _imageUrl;
        emit MetadataUpdated(_description, category, _imageUrl);
    }
    
    /// @notice Internal: Track unique traders
    function _trackUniqueTrader(address trader) private {
        if (!hasTraded[trader]) {
            hasTraded[trader] = true;
            uniqueTraders++;
        }
    }
    
    /// @notice Internal: Update volume tracking
    function _updateVolume(uint256 amount) private {
        uint256 _lastReset = lastVolumeReset;
        // Reset 24h volume if needed
        if (block.timestamp >= _lastReset + 24 hours) {
            volume24h = amount;
            lastVolumeReset = uint32(block.timestamp);
        } else {
            unchecked {
                volume24h += amount;
            }
        }
        
        unchecked {
            totalVolume += amount;
        }
    }
    
    /// @notice Internal: Snapshot price if needed
    function _snapshotPrice() private {
        // Take hourly snapshots
        if (block.timestamp >= lastSnapshotTime + 1 hours) {
            PriceSnapshot memory snapshot = PriceSnapshot({
                timestamp: block.timestamp,
                yesPrice: getPrice(true),
                noPrice: getPrice(false),
                yesReserve: yesReserve,
                noReserve: noReserve
            });
            
            if (priceHistory.length >= MAX_PRICE_HISTORY) {
                // Remove oldest, add newest
                for (uint256 i = 0; i < MAX_PRICE_HISTORY - 1; i++) {
                    priceHistory[i] = priceHistory[i + 1];
                }
                priceHistory[MAX_PRICE_HISTORY - 1] = snapshot;
            } else {
                priceHistory.push(snapshot);
            }
            
            lastSnapshotTime = block.timestamp;
            emit PriceSnapshotTaken(block.timestamp, snapshot.yesPrice, snapshot.noPrice);
        }
    }
    
    /// @notice ERC1155 receiver hook
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }
    
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
    
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
