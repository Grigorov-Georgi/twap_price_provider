# TWAP Price Provider

A Solidity project providing TWAP-based price oracles and swap functionality for Uniswap V3.

## Contracts

### TWAPPriceProvider.sol

A Time-Weighted Average Price (TWAP) oracle contract that provides reliable price quotes for token pairs using Uniswap V3 pools.

**Key Features:**
- Uses Uniswap V3's built-in TWAP functionality via `OracleLibrary`
- Configurable time interval for price averaging
- Supports multiple token pairs with different fee tiers
- Validates pool existence and manages allowed trading pairs
- Provides `consult()` function for getting TWAP-based price quotes

**Use Cases:**
- Slippage protection for swaps
- Price feeds for DeFi protocols
- MEV protection through time-averaged pricing

### UniswapV3SwapProvider.sol

A comprehensive swap contract that provides secure token swapping with built-in TWAP-based slippage protection.

**Key Features:**
- **Single-hop swaps**: Direct token-to-token swaps with exact input/output
- **Multi-hop swaps**: Complex routing through multiple pools
- **ETH support**: Native ETH handling with automatic WETH wrapping/unwrapping
- **TWAP slippage protection**: Automatic minimum/maximum amount calculation using TWAP prices
- **Configurable slippage**: Adjustable slippage tolerance

**Swap Functions:**
- `swapExactInputSingleHop()` - Swap exact input for minimum output
- `swapExactOutputSingleHop()` - Swap maximum input for exact output  
- `swapExactInputMultihop()` - Multi-hop swap with exact input
- `swapExactOutputMultihop()` - Multi-hop swap with exact output

**Security Features:**
- Pool validation through TWAPPriceProvider
- Deadline protection
- Automatic slippage calculation
- Safe token transfers using TransferHelper

## Tests

### Prerequisites

Before running tests, you need to set up environment variables:

1. Create a `.env` file in the project root:
   ```bash
   cp .env.example .env
   ```

2. Add your mainnet RPC URL to the `.env` file:
   ```
   MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
   ```

### Running Tests

```bash
forge install && forge test
```

**Note**: Tests require a mainnet RPC URL because they fork mainnet at a specific block to test against real Uniswap V3 pools and token contracts.

**CI/CD Limitation**: The automated tests in GitHub Actions are currently not working because they require an Ethereum node provider API key. To enable CI/CD, add your `MAINNET_RPC_URL` as a repository secret in GitHub Actions.

## Deployment

Use the provided deployment scripts:

```bash
# Deploy TWAP Provider
forge script script/DeployTWAPPriceProvider.s.sol --broadcast

# Deploy Swap Provider
forge script script/DeployUniswapV3SwapProvider.s.sol --broadcast
```