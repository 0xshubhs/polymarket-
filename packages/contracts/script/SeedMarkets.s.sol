// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";

contract SeedMarkets is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get deployed contract addresses from environment or use defaults
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address usdcAddr = vm.envAddress("USDC_ADDRESS");
        
        console2.log("Seeding markets...");
        console2.log("Factory:", factoryAddr);
        console2.log("USDC:", usdcAddr);
        
        MarketFactory factory = MarketFactory(factoryAddr);
        MockUSDC usdc = MockUSDC(usdcAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Give deployer some USDC
        usdc.faucet();
        
        // Create sample markets
        bytes32 market1 = factory.createMarket(
            "Will ETH reach $5000 by end of 2024?",
            "Crypto",
            deployer,
            block.timestamp + 365 days,
            false
        );
        console2.logBytes32(market1);
        
        bytes32 market2 = factory.createMarket(
            "Will BTC surpass $100,000 in 2024?",
            "Crypto",
            deployer,
            block.timestamp + 300 days,
            false
        );
        console2.logBytes32(market2);
        
        bytes32 market3 = factory.createMarket(
            "Will Solana flip Ethereum by market cap in 2024?",
            "Crypto",
            deployer,
            block.timestamp + 200 days,
            false
        );
        console2.logBytes32(market3);
        
        // Note: New architecture doesn't use AMM pools
        // Markets are traded via CTFExchange order book
        // No liquidity provision needed
        
        vm.stopBroadcast();
        
        console2.log("\n=== Markets Created ===");
        console2.log("Total markets:", factory.marketCount());
    }
}
