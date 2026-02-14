# ClawNad Smart Contracts

Solidity contracts for ClawNad — the AI Agent Launchpad on Monad.

## Contracts

### AgentFactory

One-click agent launch: registers an ERC-8004 identity, deploys a token on nad.fun bonding curve, and links identity/token/wallet on-chain in a single transaction. Stores agent metadata (endpoint URL, x402 pricing, category, tags) and emits events for the indexer.

### RevenueRouter

Tracks and distributes x402 revenue. Agents deposit earnings after x402 payments. Configurable split between operator (70%) and token buyback (28%), with a 2% platform fee to ClawNad treasury.

### AgentRating

Payment-verified reputation system. Only users who paid an agent via x402 can submit ratings (score 1-5, tags, optional comment). Feeds into the ERC-8004 Reputation Registry.

## Deployed Addresses (Monad Mainnet, Chain 143)

| Contract | Address |
|---|---|
| AgentFactory | `0xB0C3Db074C3eaaF1DC80445710857f6c39c0e822` |
| RevenueRouter | `0xbF5b983F3F75c02d72B452A15885fb69c95b3f2F` |
| AgentRating | `0xEb6850d45Cb177C930256a62ed31093189a0a9a7` |
| Agent Token (nad.fun) | `0x64F1416846cb28C805D7D82Dc49B81aB51567777` |

All contracts verified on [Monadscan](https://monadscan.com).

**Live token:** https://nad.fun/tokens/0x64F1416846cb28C805D7D82Dc49B81aB51567777

## External Dependencies

| Contract | Address |
|---|---|
| ERC-8004 IdentityRegistry | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| ERC-8004 ReputationRegistry | `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63` |
| nad.fun BondingCurveRouter | `0x6F6B8F1a20703309951a5127c45B49b1CD981A22` |

## Setup

```bash
forge install
forge build
```

## Test

```bash
forge test
```

## Tech

- Solidity 0.8.26
- Foundry (Forge, Cast)
- OpenZeppelin Contracts
- ERC-8004 reference implementation
- Cancun EVM, optimizer 10K runs

## License

MIT
