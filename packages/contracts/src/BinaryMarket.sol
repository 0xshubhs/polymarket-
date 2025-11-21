// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";

/// @title BinaryMarket
/// @notice Automated market maker for binary prediction markets using CPMM (Constant Product Market Maker)
/// @dev Implements x * y = k bonding curve for outcome token trading
contract BinaryMarket is ReentrancyGuard, IERC1155Receiver {
    using SafeERC20 for IERC20;

    ConditionalTokens public immutable conditionalTokens;
    IERC20 public immutable collateralToken;
    
    bytes32 public immutable conditionId;
    bytes32 public immutable questionId;
    address public immutable oracle;
    
    uint256 public immutable yesPositionId;
    uint256 public immutable noPositionId;
    
    string public question;
    uint256 public endTime;
    uint256 public resolutionTime;
    
    // AMM state
    uint256 public yesReserve;
    uint256 public noReserve;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidityBalance;
    
    // Trading parameters
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public feeRate = 10; // 0.1% fee
    uint256 public accumulatedFees;
    
    bool public isResolved;
    
    event LiquidityAdded(address indexed provider, uint256 amount, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 liquidity);
    event Trade(
        address indexed trader,
        bool buyYes,
        uint256 amountIn,
        uint256 amountOut,
        uint256 yesReserve,
        uint256 noReserve
    );
    event MarketResolved(uint256 yesPayoutNumerator, uint256 noPayoutNumerator);
    
    constructor(
        ConditionalTokens _conditionalTokens,
        IERC20 _collateralToken,
        address _oracle,
        string memory _question,
        uint256 _endTime
    ) {
        conditionalTokens = _conditionalTokens;
        collateralToken = _collateralToken;
        oracle = _oracle;
        question = _question;
        endTime = _endTime;
        
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
    
    /// @notice Add initial or additional liquidity to the market
    /// @param amount Amount of collateral to add (split 50/50 between YES and NO)
    function addLiquidity(uint256 amount) external nonReentrant returns (uint256 liquidity) {
        require(amount > 0, "Amount must be positive");
        require(block.timestamp < endTime, "Market ended");
        
        // Transfer collateral from user
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Split collateral into YES and NO tokens
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
        
        // Calculate liquidity tokens to mint
        if (totalLiquidity == 0) {
            // Initial liquidity
            liquidity = amount;
            yesReserve = amount;
            noReserve = amount;
        } else {
            // Proportional liquidity
            liquidity = (amount * totalLiquidity) / yesReserve;
            yesReserve += amount;
            noReserve += amount;
        }
        
        totalLiquidity += liquidity;
        liquidityBalance[msg.sender] += liquidity;
        
        emit LiquidityAdded(msg.sender, amount, liquidity);
    }
    
    /// @notice Remove liquidity from the market
    /// @param liquidity Amount of liquidity tokens to burn
    function removeLiquidity(uint256 liquidity) external nonReentrant returns (uint256 amount) {
        require(liquidity > 0, "Liquidity must be positive");
        require(liquidityBalance[msg.sender] >= liquidity, "Insufficient liquidity");
        
        // Calculate proportional amounts
        uint256 yesAmount = (liquidity * yesReserve) / totalLiquidity;
        uint256 noAmount = (liquidity * noReserve) / totalLiquidity;
        
        // Update state
        liquidityBalance[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;
        yesReserve -= yesAmount;
        noReserve -= noAmount;
        
        // Transfer YES and NO tokens to user
        conditionalTokens.safeTransferFrom(address(this), msg.sender, yesPositionId, yesAmount, "");
        conditionalTokens.safeTransferFrom(address(this), msg.sender, noPositionId, noAmount, "");
        
        amount = yesAmount; // Both are equal
        emit LiquidityRemoved(msg.sender, amount, liquidity);
    }
    
    /// @notice Buy YES or NO tokens with collateral
    /// @param buyYes True to buy YES tokens, false for NO tokens
    /// @param investmentAmount Amount of collateral to spend
    /// @param minTokensOut Minimum tokens to receive (slippage protection)
    function buy(bool buyYes, uint256 investmentAmount, uint256 minTokensOut) 
        external 
        nonReentrant 
        returns (uint256 tokensOut) 
    {
        require(investmentAmount > 0, "Amount must be positive");
        require(block.timestamp < endTime, "Market ended");
        require(yesReserve > 0 && noReserve > 0, "No liquidity");
        
        // Calculate fee
        uint256 fee = (investmentAmount * feeRate) / FEE_DENOMINATOR;
        uint256 amountAfterFee = investmentAmount - fee;
        accumulatedFees += fee;
        
        // Transfer collateral from user
        collateralToken.safeTransferFrom(msg.sender, address(this), investmentAmount);
        
        // Split collateral into conditional tokens
        collateralToken.approve(address(conditionalTokens), investmentAmount);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 0; // YES
        partition[1] = 1; // NO
        conditionalTokens.splitPosition(
            collateralToken,
            bytes32(0),
            conditionId,
            partition,
            investmentAmount
        );
        
        // Calculate tokens out using CPMM formula: Δy = y - (x * y) / (x + Δx)
        if (buyYes) {
            tokensOut = yesReserve - ((yesReserve * noReserve) / (noReserve + amountAfterFee));
            require(tokensOut >= minTokensOut, "Slippage exceeded");
            
            yesReserve -= tokensOut;
            noReserve += amountAfterFee;
            
            // Transfer YES tokens to buyer
            conditionalTokens.safeTransferFrom(address(this), msg.sender, yesPositionId, tokensOut, "");
            
            emit Trade(msg.sender, true, investmentAmount, tokensOut, yesReserve, noReserve);
        } else {
            tokensOut = noReserve - ((yesReserve * noReserve) / (yesReserve + amountAfterFee));
            require(tokensOut >= minTokensOut, "Slippage exceeded");
            
            noReserve -= tokensOut;
            yesReserve += amountAfterFee;
            
            // Transfer NO tokens to buyer
            conditionalTokens.safeTransferFrom(address(this), msg.sender, noPositionId, tokensOut, "");
            
            emit Trade(msg.sender, false, investmentAmount, tokensOut, yesReserve, noReserve);
        }
    }
    
    /// @notice Sell YES or NO tokens for collateral
    /// @param sellYes True to sell YES tokens, false for NO tokens
    /// @param tokenAmount Amount of outcome tokens to sell
    /// @param minCollateralOut Minimum collateral to receive (slippage protection)
    function sell(bool sellYes, uint256 tokenAmount, uint256 minCollateralOut) 
        external 
        nonReentrant 
        returns (uint256 collateralOut) 
    {
        require(tokenAmount > 0, "Amount must be positive");
        require(block.timestamp < endTime, "Market ended");
        require(yesReserve > 0 && noReserve > 0, "No liquidity");
        
        // Calculate collateral out using CPMM formula
        uint256 collateralBeforeFee;
        if (sellYes) {
            collateralBeforeFee = noReserve - ((yesReserve * noReserve) / (yesReserve + tokenAmount));
            
            // Transfer YES tokens from seller
            conditionalTokens.safeTransferFrom(msg.sender, address(this), yesPositionId, tokenAmount, "");
            
            yesReserve += tokenAmount;
            noReserve -= collateralBeforeFee;
            
            emit Trade(msg.sender, true, tokenAmount, collateralBeforeFee, yesReserve, noReserve);
        } else {
            collateralBeforeFee = yesReserve - ((yesReserve * noReserve) / (noReserve + tokenAmount));
            
            // Transfer NO tokens from seller
            conditionalTokens.safeTransferFrom(msg.sender, address(this), noPositionId, tokenAmount, "");
            
            noReserve += tokenAmount;
            yesReserve -= collateralBeforeFee;
            
            emit Trade(msg.sender, false, tokenAmount, collateralBeforeFee, yesReserve, noReserve);
        }
        
        // Apply fee
        uint256 fee = (collateralBeforeFee * feeRate) / FEE_DENOMINATOR;
        collateralOut = collateralBeforeFee - fee;
        accumulatedFees += fee;
        
        require(collateralOut >= minCollateralOut, "Slippage exceeded");
        
        // Merge equal amounts of YES and NO back to collateral
        uint256 mergeAmount = collateralBeforeFee;
        uint256[] memory partition = new uint256[](2);
        partition[0] = 0;
        partition[1] = 1;
        
        conditionalTokens.setApprovalForAll(address(conditionalTokens), true);
        conditionalTokens.mergePositions(
            collateralToken,
            bytes32(0),
            conditionId,
            partition,
            mergeAmount
        );
        
        // Transfer collateral to seller
        collateralToken.safeTransfer(msg.sender, collateralOut);
    }
    
    /// @notice Get current price for an outcome (probability)
    /// @param forYes True for YES price, false for NO price
    function getPrice(bool forYes) external view returns (uint256) {
        if (yesReserve == 0 || noReserve == 0) return 0;
        
        uint256 totalReserve = yesReserve + noReserve;
        if (forYes) {
            return (noReserve * 1e18) / totalReserve;
        } else {
            return (yesReserve * 1e18) / totalReserve;
        }
    }
    
    /// @notice Calculate expected tokens out for a buy order
    function calcBuyAmount(bool buyYes, uint256 investmentAmount) external view returns (uint256) {
        if (yesReserve == 0 || noReserve == 0) return 0;
        
        uint256 fee = (investmentAmount * feeRate) / FEE_DENOMINATOR;
        uint256 amountAfterFee = investmentAmount - fee;
        
        if (buyYes) {
            return yesReserve - ((yesReserve * noReserve) / (noReserve + amountAfterFee));
        } else {
            return noReserve - ((yesReserve * noReserve) / (yesReserve + amountAfterFee));
        }
    }
    
    /// @notice Calculate expected collateral out for a sell order
    function calcSellAmount(bool sellYes, uint256 tokenAmount) external view returns (uint256) {
        if (yesReserve == 0 || noReserve == 0) return 0;
        
        uint256 collateralBeforeFee;
        if (sellYes) {
            collateralBeforeFee = noReserve - ((yesReserve * noReserve) / (yesReserve + tokenAmount));
        } else {
            collateralBeforeFee = yesReserve - ((yesReserve * noReserve) / (noReserve + tokenAmount));
        }
        
        uint256 fee = (collateralBeforeFee * feeRate) / FEE_DENOMINATOR;
        return collateralBeforeFee - fee;
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
    
    /// @notice ERC1155 batch receiver hook
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
    
    /// @notice ERC165 interface support
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}