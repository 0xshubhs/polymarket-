#!/bin/bash

# Sepolia Contract Verification Script
# Run this after deployment to verify contracts on Etherscan

set -e

CHAIN_ID=11155111
RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"

# Check if ETHERSCAN_API_KEY is set
if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "❌ ETHERSCAN_API_KEY not set!"
    echo ""
    echo "Get a free API key at: https://etherscan.io/apis"
    echo "Then run: export ETHERSCAN_API_KEY=your_key_here"
    exit 1
fi

echo "✓ Etherscan API key found"
echo ""

# Contract addresses
USDC="0x3297baE90BbD190de4F275cEAE71568428e794f0"
CONDITIONAL_TOKENS="0x0294377e5B43c05652e440c52C5Cb0526f3D7Dc1"
PROTOCOL_CONFIG="0x9Bd0Bc215Ae0038D6de52533416B51465Ed8d608"
MARKET_FACTORY="0x3199d17cfa7027f91504F960DbCd34D44d284434"
OPTIMISTIC_ORACLE="0xb6C4E532894dCEDca4b858e375712674daCd7C9E"
NEG_RISK_ADAPTER="0xF1235b1782D48EbDf23673b115E51d03703463a1"
CTF_EXCHANGE="0x651524Af19c2edeb94DE60ECd0B9B361B53AAAFF"
PORTFOLIO_VIEWER="0xaFA97775b5fcDfe998Fc5dB7a01CEEBd1EcaAd48"

echo "🔍 Verifying contracts on Sepolia..."
echo ""

# Verify MockUSDC
echo "1/8 Verifying MockUSDC..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    $USDC \
    src/MockUSDC.sol:MockUSDC \
    || echo "⚠️  MockUSDC verification failed (might already be verified)"

# Verify ConditionalTokens
echo ""
echo "2/8 Verifying ConditionalTokens..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    $CONDITIONAL_TOKENS \
    src/ConditionalTokens.sol:ConditionalTokens \
    || echo "⚠️  ConditionalTokens verification failed"

# Verify ProtocolConfig
echo ""
echo "3/8 Verifying ProtocolConfig..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    $PROTOCOL_CONFIG \
    src/ProtocolConfig.sol:ProtocolConfig \
    || echo "⚠️  ProtocolConfig verification failed"

# Verify OptimisticOracle
echo ""
echo "4/8 Verifying OptimisticOracle..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,uint256)" $PROTOCOL_CONFIG 300) \
    $OPTIMISTIC_ORACLE \
    src/OptimisticOracle.sol:OptimisticOracle \
    || echo "⚠️  OptimisticOracle verification failed"

# Verify NegRiskAdapter
echo ""
echo "5/8 Verifying NegRiskAdapter..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,address)" $CONDITIONAL_TOKENS $USDC) \
    $NEG_RISK_ADAPTER \
    src/NegRiskAdapter.sol:NegRiskAdapter \
    || echo "⚠️  NegRiskAdapter verification failed"

# Verify CTFExchange
echo ""
echo "6/8 Verifying CTFExchange..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" $CONDITIONAL_TOKENS $USDC $NEG_RISK_ADAPTER) \
    $CTF_EXCHANGE \
    src/CTFExchange.sol:CTFExchange \
    || echo "⚠️  CTFExchange verification failed"

# Verify MarketFactory
echo ""
echo "7/8 Verifying MarketFactory..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address)" $CONDITIONAL_TOKENS $USDC $OPTIMISTIC_ORACLE $PROTOCOL_CONFIG) \
    $MARKET_FACTORY \
    src/MarketFactory.sol:MarketFactory \
    || echo "⚠️  MarketFactory verification failed"

# Verify PortfolioViewer
echo ""
echo "8/8 Verifying PortfolioViewer..."
forge verify-contract \
    --chain-id $CHAIN_ID \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address)" $CONDITIONAL_TOKENS) \
    $PORTFOLIO_VIEWER \
    src/PortfolioViewer.sol:PortfolioViewer \
    || echo "⚠️  PortfolioViewer verification failed"

echo ""
echo "✓ Verification complete!"
echo ""
echo "View on Etherscan:"
echo "- MockUSDC: https://sepolia.etherscan.io/address/$USDC#code"
echo "- ConditionalTokens: https://sepolia.etherscan.io/address/$CONDITIONAL_TOKENS#code"
echo "- ProtocolConfig: https://sepolia.etherscan.io/address/$PROTOCOL_CONFIG#code"
echo "- OptimisticOracle: https://sepolia.etherscan.io/address/$OPTIMISTIC_ORACLE#code"
echo "- NegRiskAdapter: https://sepolia.etherscan.io/address/$NEG_RISK_ADAPTER#code"
echo "- CTFExchange: https://sepolia.etherscan.io/address/$CTF_EXCHANGE#code"
echo "- MarketFactory: https://sepolia.etherscan.io/address/$MARKET_FACTORY#code"
echo "- PortfolioViewer: https://sepolia.etherscan.io/address/$PORTFOLIO_VIEWER#code"
