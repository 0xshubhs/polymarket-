// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ProtocolConfig} from "../src/ProtocolConfig.sol";

contract ProtocolConfigTest is Test {
    ProtocolConfig public config;
    
    address public admin;
    address public treasury = address(0x2);
    address public oracle = address(0x3);
    address public pauser = address(0x4);
    address public creator = address(0x5);
    
    function setUp() public {
        admin = address(this);
        config = new ProtocolConfig(treasury);
    }
    
    function testInitialState() public view {
        assertEq(config.treasury(), treasury);
        assertEq(config.protocolFeeRate(), 20);
        assertEq(config.maxProtocolFeeRate(), 500);
        assertEq(config.disputePeriod(), 3 days);
        assertFalse(config.paused());
        assertTrue(config.hasRole(config.DEFAULT_ADMIN_ROLE(), admin));
    }
    
    function testSetTreasury() public {
        address newTreasury = address(0x999);
        
        config.setTreasury(newTreasury);
        
        assertEq(config.treasury(), newTreasury);
    }
    
    function testCannotSetInvalidTreasury() public {
        vm.expectRevert("Invalid treasury");
        config.setTreasury(address(0));
    }
    
    function testSetProtocolFee() public {
        config.grantRole(config.FEE_MANAGER_ROLE(), admin);
        
        config.setProtocolFeeRate(100); // 1%
        
        assertEq(config.protocolFeeRate(), 100);
    }
    
    function testCannotSetFeeTooHigh() public {
        config.grantRole(config.FEE_MANAGER_ROLE(), admin);
        
        vm.expectRevert("Fee too high");
        config.setProtocolFeeRate(600); // 6% exceeds 5% max
    }
    
    function testPauseUnpause() public {
        config.grantRole(config.PAUSER_ROLE(), pauser);
        
        vm.prank(pauser);
        config.pause();
        assertTrue(config.paused());
        
        vm.prank(pauser);
        config.unpause();
        assertFalse(config.paused());
    }
    
    function testOracleApproval() public {
        config.setOracleApproval(oracle, true);
        
        assertTrue(config.approvedOracles(oracle));
        assertTrue(config.hasRole(config.ORACLE_ROLE(), oracle));
        
        config.setOracleApproval(oracle, false);
        
        assertFalse(config.approvedOracles(oracle));
    }
    
    function testValidateMarketParams() public {
        config.setOracleApproval(oracle, true);
        
        uint256 endTime = block.timestamp + 7 days;
        
        bool valid = config.validateMarketParams(oracle, endTime, "Will ETH reach $5000?");
        assertTrue(valid);
    }
    
    function testCannotValidateWithUnapprovedOracle() public {
        uint256 endTime = block.timestamp + 7 days;
        
        vm.expectRevert("Oracle not approved");
        config.validateMarketParams(oracle, endTime, "Test question");
    }
    
    function testCannotValidateInvalidDuration() public {
        config.setOracleApproval(oracle, true);
        
        // Too short
        vm.expectRevert("Invalid duration");
        config.validateMarketParams(oracle, block.timestamp + 30 minutes, "Test");
        
        // Too long
        vm.expectRevert("Invalid duration");
        config.validateMarketParams(oracle, block.timestamp + 400 days, "Test");
    }
    
    function testRegisterMarket() public {
        bool success = config.registerMarket("unique-market-hash");
        assertTrue(success);
        assertTrue(config.marketExists("unique-market-hash"));
    }
    
    function testCannotRegisterDuplicateMarket() public {
        config.registerMarket("unique-market");
        
        vm.expectRevert("Market exists");
        config.registerMarket("unique-market");
    }
    
    function testSetDisputePeriod() public {
        config.setDisputePeriod(7 days);
        
        assertEq(config.disputePeriod(), 7 days);
    }
    
    function testCannotSetInvalidDisputePeriod() public {
        vm.expectRevert("Invalid period");
        config.setDisputePeriod(30 minutes); // Too short
        
        vm.expectRevert("Invalid period");
        config.setDisputePeriod(31 days); // Too long
    }
    
    function testMarketDurationLimits() public {
        config.setMarketDurationLimits(2 hours, 180 days);
        
        assertEq(config.minMarketDuration(), 2 hours);
        assertEq(config.maxMarketDuration(), 180 days);
    }
    
    function testCanCreateMarketPermission() public {
        config.grantRole(config.MARKET_CREATOR_ROLE(), creator);
        
        assertTrue(config.canCreateMarket(creator));
        assertTrue(config.canCreateMarket(admin)); // Admin always can
        assertFalse(config.canCreateMarket(address(0x999)));
    }
    
    function testUnauthorizedCannotSetTreasury() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        config.setTreasury(address(0x888));
    }
    
    function testUnauthorizedCannotPause() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        config.pause();
    }
}
