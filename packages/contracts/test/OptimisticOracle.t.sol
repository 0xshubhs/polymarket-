// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {OptimisticOracle} from "../src/OptimisticOracle.sol";

contract OptimisticOracleTest is Test {
    MockUSDC public usdc;
    OptimisticOracle public oracle;
    
    address public arbitrator = address(1);
    address public proposer = address(2);
    address public disputer = address(3);
    
    bytes32 public identifier = keccak256("YES_OR_NO_QUERY");
    uint256 public timestamp;
    bytes public ancillaryData = abi.encodePacked("Will ETH reach $10k?");
    
    function setUp() public {
        usdc = new MockUSDC();
        oracle = new OptimisticOracle(usdc, arbitrator);
        timestamp = block.timestamp;
        
        // Fund users
        usdc.mint(proposer, 10000e6);
        usdc.mint(disputer, 10000e6);
    }
    
    function testRequestAnswer() public {
        bytes32 requestId = oracle.requestAnswer(
            identifier,
            timestamp,
            ancillaryData,
            1000e6
        );
        
        OptimisticOracle.Request memory request = oracle.getRequest(requestId);
        assertEq(request.requester, address(this));
        assertEq(request.identifier, identifier);
        assertEq(uint(request.state), uint(OptimisticOracle.RequestState.Requested));
    }
    
    function testProposeAnswer() public {
        bytes32 requestId = oracle.requestAnswer(identifier, timestamp, ancillaryData, 1000e6);
        
        bytes memory answer = abi.encode(true); // YES
        
        vm.startPrank(proposer);
        usdc.approve(address(oracle), 1000e6);
        oracle.proposeAnswer(requestId, answer);
        vm.stopPrank();
        
        OptimisticOracle.Request memory request = oracle.getRequest(requestId);
        assertEq(request.proposer, proposer);
        assertEq(uint(request.state), uint(OptimisticOracle.RequestState.Proposed));
        assertGt(request.expirationTime, block.timestamp);
    }
    
    function testSettleAfterDisputePeriod() public {
        bytes32 requestId = oracle.requestAnswer(identifier, timestamp, ancillaryData, 1000e6);
        
        bytes memory answer = abi.encode(true);
        
        vm.startPrank(proposer);
        usdc.approve(address(oracle), 1000e6);
        oracle.proposeAnswer(requestId, answer);
        vm.stopPrank();
        
        // Fast forward past dispute period
        vm.warp(block.timestamp + 2 hours + 1);
        
        oracle.settle(requestId);
        
        OptimisticOracle.Request memory request = oracle.getRequest(requestId);
        assertTrue(request.resolved);
        assertEq(uint(request.state), uint(OptimisticOracle.RequestState.Resolved));
    }
    
    function testDisputeAnswer() public {
        bytes32 requestId = oracle.requestAnswer(identifier, timestamp, ancillaryData, 1000e6);
        
        bytes memory answer = abi.encode(true);
        
        vm.startPrank(proposer);
        usdc.approve(address(oracle), 1000e6);
        oracle.proposeAnswer(requestId, answer);
        vm.stopPrank();
        
        // Dispute within period
        vm.startPrank(disputer);
        usdc.approve(address(oracle), 1000e6);
        oracle.disputeAnswer(requestId);
        vm.stopPrank();
        
        OptimisticOracle.Request memory request = oracle.getRequest(requestId);
        assertTrue(request.disputed);
        assertEq(request.disputer, disputer);
        assertEq(uint(request.state), uint(OptimisticOracle.RequestState.Disputed));
    }
    
    function testResolveDispute() public {
        bytes32 requestId = oracle.requestAnswer(identifier, timestamp, ancillaryData, 1000e6);
        
        bytes memory answer = abi.encode(true);
        
        vm.startPrank(proposer);
        usdc.approve(address(oracle), 1000e6);
        oracle.proposeAnswer(requestId, answer);
        vm.stopPrank();
        
        vm.startPrank(disputer);
        usdc.approve(address(oracle), 1000e6);
        oracle.disputeAnswer(requestId);
        vm.stopPrank();
        
        // Arbitrator resolves in favor of proposer
        bytes memory correctAnswer = abi.encode(true);
        vm.prank(arbitrator);
        oracle.resolveDispute(requestId, correctAnswer, proposer);
        
        OptimisticOracle.Request memory request = oracle.getRequest(requestId);
        assertTrue(request.resolved);
        
        // Proposer should have rewards
        assertGt(oracle.rewards(proposer), 0);
    }
    
    function testClaimRewards() public {
        bytes32 requestId = oracle.requestAnswer(identifier, timestamp, ancillaryData, 1000e6);
        
        vm.startPrank(proposer);
        usdc.approve(address(oracle), 1000e6);
        oracle.proposeAnswer(requestId, abi.encode(true));
        vm.stopPrank();
        
        vm.warp(block.timestamp + 2 hours + 1);
        oracle.settle(requestId);
        
        uint256 balanceBefore = usdc.balanceOf(proposer);
        
        vm.prank(proposer);
        oracle.claimRewards();
        
        uint256 balanceAfter = usdc.balanceOf(proposer);
        assertGt(balanceAfter, balanceBefore);
    }
    
    function testCannotSettleBeforeExpiration() public {
        bytes32 requestId = oracle.requestAnswer(identifier, timestamp, ancillaryData, 1000e6);
        
        vm.startPrank(proposer);
        usdc.approve(address(oracle), 1000e6);
        oracle.proposeAnswer(requestId, abi.encode(true));
        vm.stopPrank();
        
        // Try to settle immediately
        vm.expectRevert();
        oracle.settle(requestId);
    }
    
    function testCannotDisputeAfterPeriod() public {
        bytes32 requestId = oracle.requestAnswer(identifier, timestamp, ancillaryData, 1000e6);
        
        vm.startPrank(proposer);
        usdc.approve(address(oracle), 1000e6);
        oracle.proposeAnswer(requestId, abi.encode(true));
        vm.stopPrank();
        
        // Fast forward past dispute period
        vm.warp(block.timestamp + 2 hours + 1);
        
        // Try to dispute
        vm.startPrank(disputer);
        usdc.approve(address(oracle), 1000e6);
        vm.expectRevert();
        oracle.disputeAnswer(requestId);
        vm.stopPrank();
    }
}
