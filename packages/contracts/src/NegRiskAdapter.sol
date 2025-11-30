// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";

/// @title NegRiskAdapter
/// @notice Adapter for negative risk CTF markets
/// @dev In negative risk markets, one outcome represents "nothing happens" (e.g., a candidate NOT winning).
///      This adapter wraps the CTF to handle the specific mechanics of neg-risk markets.
///      Used by Polymarket for markets like "Will X happen before Y date?" where NO = nothing happens
contract NegRiskAdapter is IERC1155Receiver {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct NegRiskMarket {
        bytes32 questionId;
        bytes32 conditionId;
        address oracle;
        IERC20 collateral;
        uint256 yesPositionId;
        uint256 noPositionId;
        bool isNegRisk;
        bool resolved;
    }

    // ============ State Variables ============

    ConditionalTokens public immutable ctf;
    
    mapping(bytes32 => NegRiskMarket) public markets;
    mapping(bytes32 => bool) public isNegRiskMarket;

    // ============ Events ============

    event NegRiskMarketCreated(
        bytes32 indexed questionId,
        bytes32 indexed conditionId,
        address indexed oracle,
        address collateral
    );

    event NegRiskPositionSplit(
        address indexed account,
        bytes32 indexed conditionId,
        uint256 amount
    );

    event NegRiskPositionMerged(
        address indexed account,
        bytes32 indexed conditionId,
        uint256 amount
    );

    // ============ Constructor ============

    constructor(ConditionalTokens _ctf) {
        ctf = _ctf;
    }

    // ============ Market Creation ============

    /// @notice Create a negative risk market
    /// @param questionId Unique question identifier
    /// @param oracle Oracle that will resolve the market
    /// @param collateral Collateral token (e.g., USDC)
    function createNegRiskMarket(
        bytes32 questionId,
        address oracle,
        IERC20 collateral
    ) external returns (bytes32 conditionId) {
        require(oracle != address(0), "Invalid oracle");
        require(address(collateral) != address(0), "Invalid collateral");
        require(markets[questionId].oracle == address(0), "Market exists");

        // Prepare condition in CTF
        ctf.prepareCondition(questionId, oracle, 2);
        conditionId = ctf.getConditionId(oracle, questionId, 2);

        // Calculate position IDs
        bytes32 yesCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 1); // YES = index 1
        bytes32 noCollectionId = ctf.getCollectionId(bytes32(0), conditionId, 2);  // NO = index 2
        uint256 yesPositionId = ctf.getPositionId(collateral, yesCollectionId);
        uint256 noPositionId = ctf.getPositionId(collateral, noCollectionId);

        markets[questionId] = NegRiskMarket({
            questionId: questionId,
            conditionId: conditionId,
            oracle: oracle,
            collateral: collateral,
            yesPositionId: yesPositionId,
            noPositionId: noPositionId,
            isNegRisk: true,
            resolved: false
        });

        isNegRiskMarket[conditionId] = true;

        emit NegRiskMarketCreated(questionId, conditionId, oracle, address(collateral));
    }

    // ============ Position Management ============

    /// @notice Split collateral into neg-risk outcome tokens
    /// @dev For neg-risk: NO token represents "event doesn't happen" and has special properties
    /// @param questionId The market question ID
    /// @param amount Amount of collateral to split
    function splitPosition(bytes32 questionId, uint256 amount) external {
        NegRiskMarket storage market = markets[questionId];
        require(market.oracle != address(0), "Market not found");
        require(!market.resolved, "Market resolved");
        require(amount > 0, "Zero amount");

        // Transfer collateral from user
        market.collateral.safeTransferFrom(msg.sender, address(this), amount);

        // Approve CTF to spend
        market.collateral.forceApprove(address(ctf), amount);

        // Split position in CTF
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // YES outcome
        partition[1] = 2; // NO outcome (negative risk)

        ctf.splitPosition(
            market.collateral,
            bytes32(0), // No parent collection
            market.conditionId,
            partition,
            amount
        );

        // Transfer outcome tokens to user
        ctf.safeTransferFrom(address(this), msg.sender, market.yesPositionId, amount, "");
        ctf.safeTransferFrom(address(this), msg.sender, market.noPositionId, amount, "");

        emit NegRiskPositionSplit(msg.sender, market.conditionId, amount);
    }

    /// @notice Merge outcome tokens back into collateral
    /// @param questionId The market question ID
    /// @param amount Amount of outcome tokens to merge
    function mergePositions(bytes32 questionId, uint256 amount) external {
        NegRiskMarket storage market = markets[questionId];
        require(market.oracle != address(0), "Market not found");
        require(amount > 0, "Zero amount");

        // Transfer outcome tokens from user
        ctf.safeTransferFrom(msg.sender, address(this), market.yesPositionId, amount, "");
        ctf.safeTransferFrom(msg.sender, address(this), market.noPositionId, amount, "");

        // Merge positions in CTF
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // YES outcome
        partition[1] = 2; // NO outcome

        ctf.mergePositions(
            market.collateral,
            bytes32(0),
            market.conditionId,
            partition,
            amount
        );

        // Transfer collateral back to user
        market.collateral.safeTransfer(msg.sender, amount);

        emit NegRiskPositionMerged(msg.sender, market.conditionId, amount);
    }

    /// @notice Redeem winning tokens after market resolution
    /// @param questionId The market question ID
    function redeemPositions(bytes32 questionId) external {
        NegRiskMarket storage market = markets[questionId];
        require(market.oracle != address(0), "Market not found");
        require(market.resolved, "Not resolved");

        // For neg-risk, check which outcome won
        uint256[] memory indexSets = new uint256[](2);
        indexSets[0] = 1; // YES
        indexSets[1] = 2; // NO

        // Redeem through CTF
        ctf.redeemPositions(
            market.collateral,
            bytes32(0),
            market.conditionId,
            indexSets
        );

        // Transfer redeemed collateral to user
        uint256 balance = market.collateral.balanceOf(address(this));
        if (balance > 0) {
            market.collateral.safeTransfer(msg.sender, balance);
        }
    }

    // ============ View Functions ============

    /// @notice Get market details
    function getMarket(bytes32 questionId) external view returns (NegRiskMarket memory) {
        return markets[questionId];
    }

    /// @notice Check if condition is a neg-risk market
    function isNegRisk(bytes32 conditionId) external view returns (bool) {
        return isNegRiskMarket[conditionId];
    }

    /// @notice Get position IDs for a market
    function getPositionIds(bytes32 questionId) external view returns (uint256 yesId, uint256 noId) {
        NegRiskMarket storage market = markets[questionId];
        return (market.yesPositionId, market.noPositionId);
    }

    // ============ ERC1155 Receiver ============

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

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
