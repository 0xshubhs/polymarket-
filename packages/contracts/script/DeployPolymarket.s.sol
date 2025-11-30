// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {CTFExchange} from "../src/CTFExchange.sol";
import {OptimisticOracle} from "../src/OptimisticOracle.sol";

contract DeployPolymarket is Script {
    function run() external {
        // Use Anvil's default private key if PRIVATE_KEY not set
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy MockUSDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // 2. Deploy MarketFactory (which deploys CTF, Exchange, Oracle, NegRiskAdapter)
        MarketFactory factory = new MarketFactory(
            usdc,               // collateralToken
            deployer,           // operator (matching engine)
            deployer,           // feeRecipient
            deployer            // treasury
        );
        console.log("MarketFactory deployed at:", address(factory));
        
        // 3. Get deployed contract addresses
        address ctf = factory.getCTF();
        address exchange = factory.getExchange();
        address oracle = factory.getOracle();
        
        console.log("ConditionalTokens deployed at:", ctf);
        console.log("CTFExchange deployed at:", exchange);
        console.log("OptimisticOracle deployed at:", oracle);
        
        // 4. Mint test USDC to deployer
        usdc.mint(deployer, 1_000_000e6); // 1M USDC
        console.log("Minted 1,000,000 USDC to deployer");
        
        // 5. Create a sample market
        bytes32 questionId = factory.createMarket(
            "Will ETH reach $10,000 by end of 2025?",
            "Crypto",
            deployer,                    // resolver
            block.timestamp + 365 days,  // endTime (1 year)
            false                        // not negRisk
        );
        
        console.log("Sample market created with questionId:");
        console.logBytes32(questionId);
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Local/Anvil");
        console.log("USDC:", address(usdc));
        console.log("MarketFactory:", address(factory));
        console.log("CTF:", ctf);
        console.log("CTFExchange:", exchange);
        console.log("OptimisticOracle:", oracle);
        console.log("\nTo interact, use these addresses in your frontend");
    }
}
