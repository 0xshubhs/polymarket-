// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";
import {BinaryMarketV2} from "../src/BinaryMarketV2.sol";
import {ProtocolConfig} from "../src/ProtocolConfig.sol";
import {PortfolioViewer} from "../src/PortfolioViewer.sol";

contract DeployScript is Script {
    function run() external {
        // Use the signer provided by forge via keystore/private-key flags.
        // This avoids requiring the private key in the environment or terminal.
        vm.startBroadcast();

        address deployer = msg.sender;
        console2.log("Deploying contracts with address:", deployer);
        console2.log("Deployer balance:", deployer.balance);
        
        // Deploy Mock USDC for testing
        MockUSDC usdc = new MockUSDC();
        console2.log("MockUSDC deployed at:", address(usdc));
        
        // Deploy MarketFactory (creates ConditionalTokens and ProtocolConfig internally)
        MarketFactory factory = new MarketFactory(usdc, deployer);
        console2.log("MarketFactory deployed at:", address(factory));
        console2.log("ConditionalTokens deployed at:", address(factory.conditionalTokens()));
        console2.log("ProtocolConfig deployed at:", address(factory.protocolConfig()));
        
        // Deploy PortfolioViewer
        PortfolioViewer viewer = new PortfolioViewer(
            factory.conditionalTokens(),
            factory
        );
        console2.log("PortfolioViewer deployed at:", address(viewer));
        
        // Approve deployer as oracle and market creator
        ProtocolConfig config = factory.protocolConfig();
        config.setOracleApproval(deployer, true);
        config.grantRole(config.MARKET_CREATOR_ROLE(), deployer);
        console2.log("Deployer approved as oracle and market creator");
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        console2.log("\n=== Deployment Summary ===");
        console2.log("Network: Chain ID", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("USDC:", address(usdc));
        console2.log("MarketFactory:", address(factory));
        console2.log("ConditionalTokens:", address(factory.conditionalTokens()));
        console2.log("ProtocolConfig:", address(config));
        console2.log("PortfolioViewer:", address(viewer));
    }
}
