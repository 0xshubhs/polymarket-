// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {ProtocolConfig} from "../src/ProtocolConfig.sol";
import {PortfolioViewer} from "../src/PortfolioViewer.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {NegRiskAdapter} from "../src/NegRiskAdapter.sol";
import {OptimisticOracle} from "../src/OptimisticOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Multi-Chain Deployment Script
/// @notice Deploys Polymarket contracts to any supported chain
/// @dev Usage: forge script script/MultiChainDeploy.s.sol --rpc-url <network> --broadcast
contract MultiChainDeployScript is Script {
    
    // Network detection
    struct NetworkConfig {
        string name;
        uint256 chainId;
        address usdcAddress;
        bool isTestnet;
    }
    
    function getNetworkConfig() internal view returns (NetworkConfig memory) {
        uint256 chainId = block.chainid;
        
        // Ethereum Mainnet
        if (chainId == 1) {
            return NetworkConfig({
                name: "Ethereum Mainnet",
                chainId: 1,
                usdcAddress: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                isTestnet: false
            });
        }
        // Arbitrum One
        else if (chainId == 42161) {
            return NetworkConfig({
                name: "Arbitrum One",
                chainId: 42161,
                usdcAddress: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                isTestnet: false
            });
        }
        // Optimism
        else if (chainId == 10) {
            return NetworkConfig({
                name: "Optimism",
                chainId: 10,
                usdcAddress: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
                isTestnet: false
            });
        }
        // Base
        else if (chainId == 8453) {
            return NetworkConfig({
                name: "Base",
                chainId: 8453,
                usdcAddress: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                isTestnet: false
            });
        }
        // Polygon
        else if (chainId == 137) {
            return NetworkConfig({
                name: "Polygon",
                chainId: 137,
                usdcAddress: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
                isTestnet: false
            });
        }
        // Sepolia
        else if (chainId == 11155111) {
            return NetworkConfig({
                name: "Sepolia",
                chainId: 11155111,
                usdcAddress: address(0), // Deploy mock
                isTestnet: true
            });
        }
        // Arbitrum Sepolia
        else if (chainId == 421614) {
            return NetworkConfig({
                name: "Arbitrum Sepolia",
                chainId: 421614,
                usdcAddress: address(0), // Deploy mock
                isTestnet: true
            });
        }
        // Optimism Sepolia
        else if (chainId == 11155420) {
            return NetworkConfig({
                name: "Optimism Sepolia",
                chainId: 11155420,
                usdcAddress: address(0), // Deploy mock
                isTestnet: true
            });
        }
        // Base Sepolia
        else if (chainId == 84532) {
            return NetworkConfig({
                name: "Base Sepolia",
                chainId: 84532,
                usdcAddress: address(0), // Deploy mock
                isTestnet: true
            });
        }
        // Polygon Amoy
        else if (chainId == 80002) {
            return NetworkConfig({
                name: "Polygon Amoy",
                chainId: 80002,
                usdcAddress: address(0), // Deploy mock
                isTestnet: true
            });
        }
        // Localhost/Anvil
        else {
            return NetworkConfig({
                name: "Localhost",
                chainId: chainId,
                usdcAddress: address(0), // Deploy mock
                isTestnet: true
            });
        }
    }
    
    function run() external {
        vm.startBroadcast();
        
        address deployer = msg.sender;
        NetworkConfig memory config = getNetworkConfig();
        
        console2.log("\n========================================");
        console2.log("MULTI-CHAIN DEPLOYMENT");
        console2.log("========================================");
        console2.log("Network:", config.name);
        console2.log("Chain ID:", config.chainId);
        console2.log("Deployer:", deployer);
        console2.log("Balance:", deployer.balance / 1e18, "ETH");
        console2.log("========================================\n");
        
        // Step 1: Deploy or get USDC
        IERC20 usdc;
        if (config.isTestnet || config.usdcAddress == address(0)) {
            console2.log("Deploying MockUSDC...");
            MockUSDC mockUsdc = new MockUSDC();
            usdc = IERC20(address(mockUsdc));
            console2.log("MockUSDC deployed:", address(usdc));
            
            // Mint initial supply to deployer
            mockUsdc.mint(deployer, 1000000 * 1e6); // 1M USDC
            console2.log("Minted 1M USDC to deployer");
        } else {
            console2.log("Using existing USDC at:", config.usdcAddress);
            usdc = IERC20(config.usdcAddress);
        }
        
        // Step 2: Deploy ConditionalTokens
        console2.log("\nDeploying ConditionalTokens...");
        ConditionalTokens conditionalTokens = new ConditionalTokens();
        console2.log("ConditionalTokens:", address(conditionalTokens));
        
        // Step 3: Deploy ProtocolConfig
        console2.log("\nDeploying ProtocolConfig...");
        ProtocolConfig protocolConfig = new ProtocolConfig(deployer);  // Only needs treasury
        console2.log("ProtocolConfig:", address(protocolConfig));
        
        // Step 4: Deploy OptimisticOracle
        console2.log("\nDeploying OptimisticOracle...");
        OptimisticOracle oracle = new OptimisticOracle(
            usdc,
            deployer  // arbitrator
        );
        console2.log("OptimisticOracle:", address(oracle));
        
        // Step 5: Deploy NegRiskAdapter
        console2.log("\nDeploying NegRiskAdapter...");
        NegRiskAdapter negRiskAdapter = new NegRiskAdapter(conditionalTokens);
        console2.log("NegRiskAdapter:", address(negRiskAdapter));
        
        // Step 6: Deploy CTFExchange first (needed by MarketFactory)
        console2.log("\nDeploying CTFExchange...");
        CTFExchange exchange = new CTFExchange(
            conditionalTokens,
            usdc,
            deployer,  // operator
            deployer   // fee recipient
        );
        console2.log("CTFExchange:", address(exchange));
        
        // Step 7: Deploy MarketFactory
        console2.log("\nDeploying MarketFactory...");
        MarketFactory marketFactory = new MarketFactory(
            usdc,
            deployer,  // operator
            deployer,  // fee recipient
            deployer   // treasury
        );
        console2.log("MarketFactory:", address(marketFactory));
        
        // Step 8: Deploy PortfolioViewer
        console2.log("\nDeploying PortfolioViewer...");
        PortfolioViewer portfolioViewer = new PortfolioViewer(
            conditionalTokens,
            marketFactory
        );
        console2.log("PortfolioViewer:", address(portfolioViewer));
        
        // Step 9: Configure permissions
        console2.log("\nConfiguring permissions...");
        protocolConfig.grantRole(protocolConfig.MARKET_CREATOR_ROLE(), deployer);
        console2.log("Permissions configured");
        
        vm.stopBroadcast();
        
        // Final Summary
        console2.log("\n========================================");
        console2.log("DEPLOYMENT COMPLETE");
        console2.log("========================================");
        console2.log("Network:", config.name);
        console2.log("Chain ID:", vm.toString(config.chainId));
        console2.log("\nCore Contracts:");
        console2.log("  USDC:", address(usdc));
        console2.log("  ConditionalTokens:", address(conditionalTokens));
        console2.log("  ProtocolConfig:", address(protocolConfig));
        console2.log("\nMarket Infrastructure:");
        console2.log("  MarketFactory:", address(marketFactory));
        console2.log("  OptimisticOracle:", address(oracle));
        console2.log("  NegRiskAdapter:", address(negRiskAdapter));
        console2.log("\nTrading & Viewing:");
        console2.log("  CTFExchange:", address(exchange));
        console2.log("  PortfolioViewer:", address(portfolioViewer));
        console2.log("\nDeployer:", deployer);
        console2.log("========================================\n");
        
        // Save deployment info
        string memory deploymentInfo = string.concat(
            "# Deployment on ", config.name, "\n\n",
            "Chain ID: ", vm.toString(config.chainId), "\n",
            "Timestamp: ", vm.toString(block.timestamp), "\n",
            "Deployer: ", vm.toString(deployer), "\n\n",
            "## Contracts\n",
            "- USDC: ", vm.toString(address(usdc)), "\n",
            "- ConditionalTokens: ", vm.toString(address(conditionalTokens)), "\n",
            "- ProtocolConfig: ", vm.toString(address(protocolConfig)), "\n",
            "- MarketFactory: ", vm.toString(address(marketFactory)), "\n",
            "- OptimisticOracle: ", vm.toString(address(oracle)), "\n",
            "- NegRiskAdapter: ", vm.toString(address(negRiskAdapter)), "\n",
            "- CTFExchange: ", vm.toString(address(exchange)), "\n",
            "- PortfolioViewer: ", vm.toString(address(portfolioViewer)), "\n"
        );
        
        vm.writeFile(
            string.concat("deployments/", vm.toString(config.chainId), ".md"),
            deploymentInfo
        );
    }
}
