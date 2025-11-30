// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";

/// @title CTFExchange
/// @notice Central Limit Order Book (CLOB) exchange for Conditional Token Framework
/// @dev Matches limit orders off-chain, settles on-chain. Based on Polymarket's architecture.
contract CTFExchange is ReentrancyGuard, IERC1155Receiver, EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // ============ Structs ============

    /// @notice Limit order structure
    struct Order {
        bytes32 salt;           // Unique salt for order identification
        address maker;          // Order creator
        address signer;         // Address that signed the order (can be different from maker)
        address taker;          // Specific taker address (address(0) for any taker)
        uint256 tokenId;        // CTF position ID
        uint256 makerAmount;    // Amount maker is selling
        uint256 takerAmount;    // Amount taker must provide
        uint256 expiration;     // Expiration timestamp
        uint256 nonce;          // Nonce for cancellations
        uint256 feeRateBps;     // Fee rate in basis points (for maker)
        Side side;              // BUY or SELL
        SignatureType signatureType; // EOA or POLY_PROXY or POLY_GNOSIS_SAFE
    }

    enum Side {
        BUY,    // Buying outcome tokens (providing collateral)
        SELL    // Selling outcome tokens (receiving collateral)
    }

    enum SignatureType {
        EOA,
        POLY_PROXY,
        POLY_GNOSIS_SAFE
    }

    /// @notice Match result for order execution
    struct MatchResult {
        bytes32 makerOrderHash;
        bytes32 takerOrderHash;
        uint256 makerAmountFilled;
        uint256 takerAmountFilled;
        uint256 makerFee;
        uint256 takerFee;
    }

    // ============ State Variables ============

    ConditionalTokens public immutable ctf;
    IERC20 public immutable collateralToken;
    address public operator;        // Can be a relayer/matching engine
    address public feeRecipient;    // Protocol fee recipient
    
    uint256 public makerFeeBps;     // Maker fee (typically 0)
    uint256 public takerFeeBps;     // Taker fee (typically 20 = 0.2%)
    uint256 public constant MAX_FEE_BPS = 500; // 5% max
    uint256 public constant BPS_DENOMINATOR = 10000;

    // Order tracking
    mapping(bytes32 => uint256) public filled;      // orderHash => filledAmount
    mapping(bytes32 => bool) public cancelled;      // orderHash => cancelled
    mapping(address => uint256) public nonces;      // user => current nonce

    // ============ EIP-712 Constants ============

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(bytes32 salt,address maker,address signer,address taker,uint256 tokenId,uint256 makerAmount,uint256 takerAmount,uint256 expiration,uint256 nonce,uint256 feeRateBps,uint8 side,uint8 signatureType)"
    );

    // ============ Events ============

    event OrdersMatched(
        bytes32 indexed makerOrderHash,
        bytes32 indexed takerOrderHash,
        address indexed maker,
        address taker,
        uint256 makerAmountFilled,
        uint256 takerAmountFilled,
        uint256 makerFee,
        uint256 takerFee
    );

    event OrderCancelled(bytes32 indexed orderHash);
    event NonceIncremented(address indexed user, uint256 newNonce);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeeUpdated(uint256 makerFeeBps, uint256 takerFeeBps);
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);

    // ============ Modifiers ============

    modifier onlyOperator() {
        require(msg.sender == operator, "Not operator");
        _;
    }

    // ============ Constructor ============

    constructor(
        ConditionalTokens _ctf,
        IERC20 _collateralToken,
        address _operator,
        address _feeRecipient
    ) EIP712("CTFExchange", "1") {
        ctf = _ctf;
        collateralToken = _collateralToken;
        operator = _operator;
        feeRecipient = _feeRecipient;
        
        makerFeeBps = 0;    // No maker fee
        takerFeeBps = 20;   // 0.2% taker fee
    }

    // ============ Core Matching Functions ============

    /// @notice Match and fill orders (called by off-chain matching engine)
    /// @param makerOrder Maker's signed order
    /// @param takerOrder Taker's signed order
    /// @param makerSignature Maker's signature
    /// @param takerSignature Taker's signature
    /// @param fillAmount Amount to fill (in maker's token terms)
    function matchOrders(
        Order calldata makerOrder,
        Order calldata takerOrder,
        bytes calldata makerSignature,
        bytes calldata takerSignature,
        uint256 fillAmount
    ) external nonReentrant onlyOperator returns (MatchResult memory) {
        // Validate orders
        bytes32 makerHash = _validateOrder(makerOrder, makerSignature);
        bytes32 takerHash = _validateOrder(takerOrder, takerSignature);

        require(makerOrder.side != takerOrder.side, "Same side orders");
        require(makerOrder.tokenId == takerOrder.tokenId, "Token mismatch");
        
        // Check taker restrictions
        if (makerOrder.taker != address(0)) {
            require(makerOrder.taker == takerOrder.maker, "Invalid taker");
        }
        if (takerOrder.taker != address(0)) {
            require(takerOrder.taker == makerOrder.maker, "Invalid taker");
        }

        // Calculate fill amounts
        uint256 makerFillAmount = fillAmount;
        uint256 takerFillAmount = (fillAmount * takerOrder.makerAmount) / makerOrder.makerAmount;

        require(makerFillAmount > 0 && takerFillAmount > 0, "Zero fill");
        require(filled[makerHash] + makerFillAmount <= makerOrder.makerAmount, "Maker overfill");
        require(filled[takerHash] + takerFillAmount <= takerOrder.makerAmount, "Taker overfill");

        // Calculate fees
        uint256 makerFee = (makerFillAmount * makerFeeBps) / BPS_DENOMINATOR;
        uint256 takerFee = (takerFillAmount * takerFeeBps) / BPS_DENOMINATOR;

        // Update filled amounts
        filled[makerHash] += makerFillAmount;
        filled[takerHash] += takerFillAmount;

        // Execute settlement
        _settleMatch(makerOrder, takerOrder, makerFillAmount, takerFillAmount, makerFee, takerFee);

        emit OrdersMatched(
            makerHash,
            takerHash,
            makerOrder.maker,
            takerOrder.maker,
            makerFillAmount,
            takerFillAmount,
            makerFee,
            takerFee
        );

        return MatchResult({
            makerOrderHash: makerHash,
            takerOrderHash: takerHash,
            makerAmountFilled: makerFillAmount,
            takerAmountFilled: takerFillAmount,
            makerFee: makerFee,
            takerFee: takerFee
        });
    }

    /// @notice Settle the matched orders
    function _settleMatch(
        Order calldata makerOrder,
        Order calldata takerOrder,
        uint256 makerFillAmount,
        uint256 takerFillAmount,
        uint256 makerFee,
        uint256 takerFee
    ) private {
        if (makerOrder.side == Side.SELL) {
            // Maker sells tokens for collateral
            // Maker -> Exchange: outcome tokens
            ctf.safeTransferFrom(
                makerOrder.maker,
                address(this),
                makerOrder.tokenId,
                makerFillAmount,
                ""
            );

            // Taker -> Exchange: collateral (including fee)
            collateralToken.safeTransferFrom(
                takerOrder.maker,
                address(this),
                takerFillAmount + takerFee
            );

            // Exchange -> Maker: collateral (minus maker fee)
            collateralToken.safeTransfer(makerOrder.maker, takerFillAmount - makerFee);

            // Exchange -> Taker: outcome tokens
            ctf.safeTransferFrom(
                address(this),
                takerOrder.maker,
                makerOrder.tokenId,
                makerFillAmount,
                ""
            );

            // Collect fees
            if (makerFee + takerFee > 0) {
                collateralToken.safeTransfer(feeRecipient, makerFee + takerFee);
            }
        } else {
            // Maker buys tokens with collateral
            // Maker -> Exchange: collateral (including fee)
            collateralToken.safeTransferFrom(
                makerOrder.maker,
                address(this),
                makerFillAmount + makerFee
            );

            // Taker -> Exchange: outcome tokens
            ctf.safeTransferFrom(
                takerOrder.maker,
                address(this),
                takerOrder.tokenId,
                takerFillAmount,
                ""
            );

            // Exchange -> Taker: collateral (minus taker fee)
            collateralToken.safeTransfer(takerOrder.maker, makerFillAmount - takerFee);

            // Exchange -> Maker: outcome tokens
            ctf.safeTransferFrom(
                address(this),
                makerOrder.maker,
                takerOrder.tokenId,
                takerFillAmount,
                ""
            );

            // Collect fees
            if (makerFee + takerFee > 0) {
                collateralToken.safeTransfer(feeRecipient, makerFee + takerFee);
            }
        }
    }

    // ============ Order Validation ============

    /// @notice Validate order and signature
    function _validateOrder(Order calldata order, bytes calldata signature) private view returns (bytes32) {
        require(order.expiration > block.timestamp, "Order expired");
        require(order.nonce >= nonces[order.maker], "Invalid nonce");
        require(order.makerAmount > 0 && order.takerAmount > 0, "Zero amount");

        bytes32 orderHash = hashOrder(order);
        require(!cancelled[orderHash], "Order cancelled");

        // Verify signature
        bytes32 digest = _hashTypedDataV4(orderHash);
        address recoveredSigner = digest.recover(signature);
        require(recoveredSigner == order.signer, "Invalid signature");
        require(order.signer == order.maker, "Signer mismatch"); // Simplified for now

        return orderHash;
    }

    /// @notice Hash an order for signing
    function hashOrder(Order calldata order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.salt,
                order.maker,
                order.signer,
                order.taker,
                order.tokenId,
                order.makerAmount,
                order.takerAmount,
                order.expiration,
                order.nonce,
                order.feeRateBps,
                order.side,
                order.signatureType
            )
        );
    }

    // ============ Order Management ============

    /// @notice Cancel an order
    function cancelOrder(Order calldata order) external {
        require(msg.sender == order.maker, "Not maker");
        bytes32 orderHash = hashOrder(order);
        cancelled[orderHash] = true;
        emit OrderCancelled(orderHash);
    }

    /// @notice Cancel all orders by incrementing nonce
    function incrementNonce() external {
        nonces[msg.sender]++;
        emit NonceIncremented(msg.sender, nonces[msg.sender]);
    }

    /// @notice Check if order can be filled
    function getOrderStatus(Order calldata order) external view returns (
        bytes32 orderHash,
        uint256 filledAmount,
        bool isCancelled,
        bool isExpired,
        bool isValid
    ) {
        orderHash = hashOrder(order);
        filledAmount = filled[orderHash];
        isCancelled = cancelled[orderHash];
        isExpired = order.expiration <= block.timestamp;
        isValid = !isCancelled && !isExpired && order.nonce >= nonces[order.maker];
    }

    // ============ Admin Functions ============

    /// @notice Update fee recipient
    function setFeeRecipient(address _feeRecipient) external onlyOperator {
        require(_feeRecipient != address(0), "Zero address");
        address old = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(old, _feeRecipient);
    }

    /// @notice Update fee rates
    function setFees(uint256 _makerFeeBps, uint256 _takerFeeBps) external onlyOperator {
        require(_makerFeeBps <= MAX_FEE_BPS, "Maker fee too high");
        require(_takerFeeBps <= MAX_FEE_BPS, "Taker fee too high");
        makerFeeBps = _makerFeeBps;
        takerFeeBps = _takerFeeBps;
        emit FeeUpdated(_makerFeeBps, _takerFeeBps);
    }

    /// @notice Update operator
    function setOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "Zero address");
        address old = operator;
        operator = _operator;
        emit OperatorUpdated(old, _operator);
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
