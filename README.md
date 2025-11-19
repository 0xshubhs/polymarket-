# Polymarket Clone

A production-ready decentralized prediction markets platform built with Solidity smart contracts and a Next.js frontend.

## 🏗️ Architecture

This is a monorepo project with the following structure:

```
polymarket/
├── packages/
│   ├── contracts/     # Solidity smart contracts (Foundry)
│   ├── frontend/      # Next.js + React frontend
│   └── backend/       # Express.js indexer (optional)
```

## 🚀 Features

### Smart Contracts
- **ConditionalTokens**: ERC1155 implementation for outcome tokens
- **BinaryMarket**: CPMM (Constant Product Market Maker) AMM for binary markets
- **MarketFactory**: Factory pattern for creating new markets
- **MockUSDC**: Test USDC token for local development

### Frontend
- Next.js 16 with App Router
- RainbowKit for wallet connection
- Wagmi & Viem for Web3 interactions
- Tailwind CSS for styling
- Real-time market data fetching
- Trading interface with slippage protection

### Key Features
- ✅ Production-ready smart contracts with comprehensive tests
- ✅ CPMM automated market maker
- ✅ ERC1155 conditional tokens
- ✅ Oracle-based market resolution
- ✅ Liquidity provision
- ✅ Trading with slippage protection
- ✅ Real-time price updates
- ✅ Responsive UI

## 📋 Prerequisites

- Node.js 18+ and pnpm
- Foundry (for smart contracts)
- Git

## 🛠️ Setup & Installation

### 1. Clone and Install Dependencies

```bash
cd polymarket
pnpm install
```

### 2. Start Local Blockchain (Anvil)

```bash
# In a separate terminal
anvil
```

This will start a local Ethereum node at `http://127.0.0.1:8545` with pre-funded test accounts.

### 3. Deploy Smart Contracts

```bash
cd packages/contracts

# Run tests
forge test

# Deploy contracts to Anvil
forge script script/Deploy.s.sol:DeployScript --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# Seed markets with sample data
FACTORY_ADDRESS=<factory-address> USDC_ADDRESS=<usdc-address> forge script script/SeedMarkets.s.sol:SeedMarkets --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

### 4. Start Frontend

```bash
cd packages/frontend

# Update contract addresses in lib/contracts/addresses.ts with deployed addresses

# Start development server
pnpm dev
```

The frontend will be available at `http://localhost:3000`

### 5. Connect Wallet

1. Install MetaMask or another Web3 wallet
2. Add Anvil network:
   - Network Name: Anvil Local
   - RPC URL: http://127.0.0.1:8545
   - Chain ID: 31337
   - Currency Symbol: ETH
3. Import an Anvil test account using private key from the anvil output
4. Get test USDC by interacting with the MockUSDC contract

## 🧪 Testing

### Smart Contract Tests

```bash
cd packages/contracts

# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testBuyYesTokens

# Run with gas reporting
forge test --gas-report
```

Test Coverage:
- ✅ Conditional token splitting and merging
- ✅ Market resolution and payout redemption
- ✅ CPMM trading (buy/sell)
- ✅ Liquidity provision
- ✅ Fee accumulation
- ✅ Slippage protection
- ✅ Price impact calculations
- ✅ Fuzz testing

## 📝 Smart Contract Details

### ConditionalTokens.sol
ERC1155 token representing conditional outcomes. Handles:
- Condition preparation
- Position splitting (collateral → outcome tokens)
- Position merging (outcome tokens → collateral)
- Condition resolution
- Payout redemption

### BinaryMarket.sol
Automated market maker for binary prediction markets:
- CPMM formula: `x * y = k`
- 0.1% trading fee
- Liquidity provision/removal
- Buy/sell outcome tokens
- Price calculation based on reserves

### MarketFactory.sol
Factory for creating and tracking markets:
- Create new binary markets
- Track all deployed markets
- Shared ConditionalTokens instance

### Deployed Addresses (Anvil)
```
MockUSDC: 0x5FbDB2315678afecb367f032d93F642f64180aa3
MarketFactory: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
ConditionalTokens: 0xCafac3dD18aC6c6e92c921884f9E4176737C052c
```

## 🎯 Usage Example

### Creating a Market

```solidity
// Deploy via MarketFactory
factory.createMarket(
    oracleAddress,
    "Will ETH reach $5000 by Dec 2025?",
    1735689600 // End timestamp
);
```

### Adding Liquidity

```solidity
// Approve USDC
usdc.approve(marketAddress, amount);

// Add liquidity (splits into YES/NO tokens)
market.addLiquidity(10000 * 10**6); // 10k USDC
```

### Trading

```solidity
// Approve USDC
usdc.approve(marketAddress, investmentAmount);

// Buy YES tokens
market.buy(
    true,                    // buyYes
    1000 * 10**6,           // 1000 USDC
    950 * 10**6             // minTokensOut (slippage protection)
);
```

## 🔐 Security Considerations

- ✅ ReentrancyGuard on all state-changing functions
- ✅ SafeERC20 for token transfers
- ✅ Slippage protection on trades
- ✅ Comprehensive input validation
- ✅ Access control for market resolution
- ⚠️ This is a demo project - DO NOT use in production without audit

## 📊 Project Structure

```
packages/contracts/
├── src/
│   ├── ConditionalTokens.sol
│   ├── BinaryMarket.sol
│   ├── MarketFactory.sol
│   └── MockUSDC.sol
├── test/
│   ├── ConditionalTokens.t.sol
│   ├── BinaryMarket.t.sol
│   └── MarketFactory.t.sol
└── script/
    ├── Deploy.s.sol
    └── SeedMarkets.s.sol

packages/frontend/
├── app/
│   ├── page.tsx
│   ├── layout.tsx
│   ├── providers.tsx
│   ├── market/[address]/page.tsx
│   └── portfolio/page.tsx
├── components/
│   ├── Header.tsx
│   └── MarketsList.tsx
└── lib/
    └── contracts/
        ├── addresses.ts
        └── *.json (ABIs)
```

## 🛣️ Roadmap

- [ ] Backend API for event indexing
- [ ] Historical price charts
- [ ] Advanced order types (limit orders)
- [ ] Multi-outcome markets
- [ ] Market categories and search
- [ ] Social features (comments, sharing)
- [ ] Mobile app
- [ ] Mainnet deployment

## 📄 License

MIT

## 🤝 Contributing

Contributions welcome! Please open an issue or PR.

## ⚠️ Disclaimer

This is a demo/educational project. Smart contracts have not been audited. Do not use with real funds without proper security review.
