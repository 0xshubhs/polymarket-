// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title ProtocolConfig
/// @notice Centralized configuration and access control for the protocol
/// @dev Manages roles, fees, and protocol-wide parameters
contract ProtocolConfig is AccessControl, Pausable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    
    // Protocol parameters
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // Packed slot 1: fees and durations
    uint16 public protocolFeeRate; // 0-10000 basis points
    uint16 public maxProtocolFeeRate; // 0-10000 basis points
    uint32 public minMarketDuration; // seconds
    uint32 public maxMarketDuration; // seconds
    uint32 public disputePeriod; // seconds
    address public treasury; // 160 bits, fills slot
    
    mapping(address => bool) public approvedOracles;
    mapping(string => bool) public marketExists; // Prevent duplicate markets
    
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event OracleApproved(address indexed oracle, bool approved);
    event DisputePeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event MarketDurationLimitsUpdated(uint256 minDuration, uint256 maxDuration);
    
    constructor(address _treasury) {
        require(_treasury != address(0), "Invalid treasury");
        
        treasury = _treasury;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MARKET_CREATOR_ROLE, msg.sender);
        _grantRole(FEE_MANAGER_ROLE, msg.sender);
    }
    
    /// @notice Pause all protocol operations
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /// @notice Unpause protocol operations
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /// @notice Update treasury address
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "Invalid treasury");
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }
    
    /// @notice Update protocol fee rate
    function setProtocolFeeRate(uint256 _feeRate) external onlyRole(FEE_MANAGER_ROLE) {
        require(_feeRate <= maxProtocolFeeRate, "Fee too high");
        uint256 oldFee = protocolFeeRate;
        protocolFeeRate = uint16(_feeRate);
        emit ProtocolFeeUpdated(oldFee, _feeRate);
    }
    
    /// @notice Approve or revoke oracle
    function setOracleApproval(address oracle, bool approved) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(oracle != address(0), "Invalid oracle");
        approvedOracles[oracle] = approved;
        if (approved) {
            _grantRole(ORACLE_ROLE, oracle);
        } else {
            _revokeRole(ORACLE_ROLE, oracle);
        }
        emit OracleApproved(oracle, approved);
    }
    
    /// @notice Update dispute period
    function setDisputePeriod(uint256 _period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_period >= 1 hours && _period <= 30 days, "Invalid period");
        uint256 old = disputePeriod;
        disputePeriod = uint32(_period);
        emit DisputePeriodUpdated(old, _period);
    }
    
    /// @notice Update market duration limits
    function setMarketDurationLimits(uint256 _min, uint256 _max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_min >= 1 hours && _min < _max, "Invalid limits");
        require(_max <= 730 days, "Max too long");
        minMarketDuration = uint32(_min);
        maxMarketDuration = uint32(_max);
        emit MarketDurationLimitsUpdated(_min, _max);
    }
    
    /// @notice Register a market to prevent duplicates
    function registerMarket(string calldata questionHash) external returns (bool) {
        require(!marketExists[questionHash], "Market exists");
        marketExists[questionHash] = true;
        return true;
    }
    
    /// @notice Check if market creator has permission
    function canCreateMarket(address creator) external view returns (bool) {
        return hasRole(MARKET_CREATOR_ROLE, creator) || hasRole(DEFAULT_ADMIN_ROLE, creator);
    }
    
    /// @notice Validate market parameters
    function validateMarketParams(
        address oracle,
        uint256 endTime,
        string calldata question
    ) external view returns (bool) {
        require(approvedOracles[oracle], "Oracle not approved");
        require(bytes(question).length > 0 && bytes(question).length <= 500, "Invalid question");
        
        uint256 duration = endTime - block.timestamp;
        require(duration >= minMarketDuration && duration <= maxMarketDuration, "Invalid duration");
        
        return true;
    }
    
    /// @notice Grant admin role to new address (for testing/migrations)
    function transferAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0), "Invalid address");
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    }
}
