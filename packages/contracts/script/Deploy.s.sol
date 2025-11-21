// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";

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
        
        // Deploy MarketFactory
        MarketFactory factory = new MarketFactory(usdc);
        console2.log("MarketFactory deployed at:", address(factory));
        console2.log("ConditionalTokens deployed at:", address(factory.conditionalTokens()));
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        console2.log("\n=== Deployment Summary ===");
        console2.log("Network: Anvil Local Testnet");
        console2.log("USDC:", address(usdc));
        console2.log("MarketFactory:", address(factory));
        console2.log("ConditionalTokens:", address(factory.conditionalTokens()));
    }
}
