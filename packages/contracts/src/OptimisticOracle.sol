// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title OptimisticOracle
/// @notice Simplified UMA-style optimistic oracle for market resolution
/// @dev Markets can be proposed, disputed, and resolved with economic guarantees
contract OptimisticOracle {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct Request {
        address requester;          // Who requested the resolution
        address proposer;           // Who proposed the answer
        address disputer;           // Who disputed (if any)
        bytes32 identifier;         // Question identifier
        uint256 timestamp;          // Request timestamp
        bytes ancillaryData;        // Additional context (question, market details)
        bytes proposedAnswer;       // Proposed answer (YES/NO/INVALID encoded)
        uint256 bond;               // Bond amount required
        uint256 proposalTime;       // When answer was proposed
        uint256 expirationTime;     // When dispute period ends
        bool resolved;              // Whether resolved
        bool disputed;              // Whether disputed
        RequestState state;         // Current state
    }

    enum RequestState {
        Requested,      // Request created, awaiting proposal
        Proposed,       // Answer proposed, in dispute period
        Disputed,       // Disputed, needs arbitration
        Resolved        // Finalized
    }

    // ============ State Variables ============

    IERC20 public immutable bondToken;      // Token used for bonds (typically USDC)
    address public arbitrator;              // Can resolve disputes
    
    uint256 public defaultBond;             // Default bond amount
    uint256 public disputePeriod;           // Time to dispute (e.g., 2 hours)
    uint256 public constant MIN_BOND = 100e6;       // 100 USDC minimum
    uint256 public constant MAX_DISPUTE_PERIOD = 7 days;

    mapping(bytes32 => Request) public requests;
    mapping(address => uint256) public rewards;     // Claimable rewards for correct proposers/disputers

    // ============ Events ============

    event RequestCreated(
        bytes32 indexed requestId,
        address indexed requester,
        bytes32 indexed identifier,
        uint256 timestamp,
        bytes ancillaryData,
        uint256 bond
    );

    event AnswerProposed(
        bytes32 indexed requestId,
        address indexed proposer,
        bytes proposedAnswer,
        uint256 expirationTime
    );

    event AnswerDisputed(
        bytes32 indexed requestId,
        address indexed disputer,
        uint256 timestamp
    );

    event RequestResolved(
        bytes32 indexed requestId,
        bytes answer,
        address resolver
    );

    event BondUpdated(uint256 oldBond, uint256 newBond);
    event DisputePeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    // ============ Modifiers ============

    modifier onlyArbitrator() {
        require(msg.sender == arbitrator, "Not arbitrator");
        _;
    }

    // ============ Constructor ============

    constructor(IERC20 _bondToken, address _arbitrator) {
        bondToken = _bondToken;
        arbitrator = _arbitrator;
        defaultBond = 1000e6;        // 1000 USDC default
        disputePeriod = 2 hours;     // 2 hour dispute window
    }

    // ============ Core Functions ============

    /// @notice Request a price/answer for a question
    /// @param identifier Question type identifier
    /// @param timestamp Request timestamp
    /// @param ancillaryData Encoded question and market details
    /// @param bond Bond amount (use 0 for default)
    function requestAnswer(
        bytes32 identifier,
        uint256 timestamp,
        bytes calldata ancillaryData,
        uint256 bond
    ) external returns (bytes32 requestId) {
        if (bond == 0) bond = defaultBond;
        require(bond >= MIN_BOND, "Bond too low");

        requestId = keccak256(
            abi.encodePacked(identifier, timestamp, ancillaryData, msg.sender)
        );
        
        require(requests[requestId].timestamp == 0, "Request exists");

        requests[requestId] = Request({
            requester: msg.sender,
            proposer: address(0),
            disputer: address(0),
            identifier: identifier,
            timestamp: timestamp,
            ancillaryData: ancillaryData,
            proposedAnswer: "",
            bond: bond,
            proposalTime: 0,
            expirationTime: 0,
            resolved: false,
            disputed: false,
            state: RequestState.Requested
        });

        emit RequestCreated(requestId, msg.sender, identifier, timestamp, ancillaryData, bond);
    }

    /// @notice Propose an answer to a request
    /// @param requestId The request to answer
    /// @param proposedAnswer The proposed answer (encoded outcome data)
    function proposeAnswer(
        bytes32 requestId,
        bytes calldata proposedAnswer
    ) external {
        Request storage request = requests[requestId];
        require(request.timestamp != 0, "Request not found");
        require(request.state == RequestState.Requested, "Invalid state");
        require(proposedAnswer.length > 0, "Empty answer");

        // Take bond from proposer
        bondToken.safeTransferFrom(msg.sender, address(this), request.bond);

        request.proposer = msg.sender;
        request.proposedAnswer = proposedAnswer;
        request.proposalTime = block.timestamp;
        request.expirationTime = block.timestamp + disputePeriod;
        request.state = RequestState.Proposed;

        emit AnswerProposed(requestId, msg.sender, proposedAnswer, request.expirationTime);
    }

    /// @notice Dispute a proposed answer
    /// @param requestId The request to dispute
    function disputeAnswer(bytes32 requestId) external {
        Request storage request = requests[requestId];
        require(request.state == RequestState.Proposed, "Not disputable");
        require(block.timestamp < request.expirationTime, "Dispute period ended");

        // Take bond from disputer
        bondToken.safeTransferFrom(msg.sender, address(this), request.bond);

        request.disputer = msg.sender;
        request.disputed = true;
        request.state = RequestState.Disputed;

        emit AnswerDisputed(requestId, msg.sender, block.timestamp);
    }

    /// @notice Settle a request after dispute period (if not disputed)
    /// @param requestId The request to settle
    function settle(bytes32 requestId) external {
        Request storage request = requests[requestId];
        require(request.state == RequestState.Proposed, "Invalid state");
        require(block.timestamp >= request.expirationTime, "Still in dispute period");

        request.resolved = true;
        request.state = RequestState.Resolved;

        // Reward proposer with their bond back + requester's reward
        rewards[request.proposer] += request.bond;

        emit RequestResolved(requestId, request.proposedAnswer, request.proposer);
    }

    /// @notice Resolve a disputed request (arbitrator only)
    /// @param requestId The disputed request
    /// @param answer The correct answer
    /// @param winner Who was correct (proposer or disputer)
    function resolveDispute(
        bytes32 requestId,
        bytes calldata answer,
        address winner
    ) external onlyArbitrator {
        Request storage request = requests[requestId];
        require(request.state == RequestState.Disputed, "Not disputed");
        require(winner == request.proposer || winner == request.disputer, "Invalid winner");

        request.resolved = true;
        request.state = RequestState.Resolved;
        request.proposedAnswer = answer;

        // Winner gets both bonds
        rewards[winner] += request.bond * 2;

        emit RequestResolved(requestId, answer, winner);
    }

    /// @notice Get the settled answer for a request
    /// @param requestId The request ID
    function getAnswer(bytes32 requestId) external view returns (bytes memory) {
        Request storage request = requests[requestId];
        require(request.resolved, "Not resolved");
        return request.proposedAnswer;
    }

    /// @notice Check if request has been resolved
    function hasAnswer(bytes32 requestId) external view returns (bool) {
        return requests[requestId].resolved;
    }

    /// @notice Claim accumulated rewards
    function claimRewards() external {
        uint256 amount = rewards[msg.sender];
        require(amount > 0, "No rewards");
        
        rewards[msg.sender] = 0;
        bondToken.safeTransfer(msg.sender, amount);
    }

    // ============ Admin Functions ============

    /// @notice Update default bond amount
    function setDefaultBond(uint256 _bond) external onlyArbitrator {
        require(_bond >= MIN_BOND, "Bond too low");
        uint256 old = defaultBond;
        defaultBond = _bond;
        emit BondUpdated(old, _bond);
    }

    /// @notice Update dispute period
    function setDisputePeriod(uint256 _period) external onlyArbitrator {
        require(_period > 0 && _period <= MAX_DISPUTE_PERIOD, "Invalid period");
        uint256 old = disputePeriod;
        disputePeriod = _period;
        emit DisputePeriodUpdated(old, _period);
    }

    /// @notice Update arbitrator
    function setArbitrator(address _arbitrator) external onlyArbitrator {
        require(_arbitrator != address(0), "Zero address");
        arbitrator = _arbitrator;
    }

    // ============ View Functions ============

    /// @notice Get full request details
    function getRequest(bytes32 requestId) external view returns (Request memory) {
        return requests[requestId];
    }

    /// @notice Check if answer can be disputed
    function canDispute(bytes32 requestId) external view returns (bool) {
        Request storage request = requests[requestId];
        return request.state == RequestState.Proposed && 
               block.timestamp < request.expirationTime;
    }

    /// @notice Check if request can be settled
    function canSettle(bytes32 requestId) external view returns (bool) {
        Request storage request = requests[requestId];
        return request.state == RequestState.Proposed && 
               block.timestamp >= request.expirationTime;
    }
}
