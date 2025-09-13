# zpx-lp-vault

This repository is a Foundry monorepo implementing a cross-chain hub-and-spoke liquidity vault. It provides a multi-asset Arbitrum Hub with a USD-denominated yield share token (USDzy), optional ZPX incentive streaming, and Phase‑2 spoke vaults and routing for cross-chain liquidity balancing via adapters and a deployer Factory.

Key properties: UUPS upgradeability, role-gated admin surfaces (OpenZeppelin AccessControl), pausability, SafeERC20 usage and explicit replay protection for cross-chain messages.

## Table of contents

- Architecture at a glance
- Diagrams
- Diagram (flows)
- Contract inventory
- Key protocol behaviors
  - Cross-chain Message Schema
  - Roles & Permissions Matrix
  - Protocol Parameters & Defaults
- Deployment
  - Environment variables (consolidated)
- Testing & CI
- Security, upgradeability & storage
- Operational runbook quicklinks
- Quick Ops Runbook
- Roadmap & versioning
- License & contact

## Architecture at a glance

Phase-1 → Phase-1.5 → Phase-2

- Phase-1 (Arbitrum Hub): `src/Hub.sol` + `src/USDzy.sol` — multi-asset deposits (USDC/USDT/DAI), price feeds, canonical PPS (`pps6()`) and a 2-hour withdraw queue.
- Phase-1.5 (ZPX incentives): `src/zpx/ZPXArb.sol`, `src/zpx/MintGate_Arb.sol`, `src/zpx/ZPXRewarder.sol` — optional ZPX token, endpoint-pinned minter and streaming/top-up rewarder.
- Phase-2 (Spokes/Router/Messaging/Factory): `src/spoke/SpokeVault.sol`, `src/router/Router.sol`, `src/messaging/MessagingEndpointReceiver.sol`, `src/usdzy/USDzyRemoteMinter.sol`, `src/factory/Factory.sol`, `src/messaging/MockAdapter.sol` — spoke vaults (ERC-4626 surface with LP disabled), router TVL ring buffer and rebalance, adapter → receiver mint, and a Factory to deploy and wire proxies.

## Diagrams

Design diagrams and inline ASCII diagrams were removed from this README to avoid renderer incompatibilities in some previewers. If visual assets are desired they can be exported as SVG/PNG and added under `docs/assets/`.


## Flow summaries

High-level flow summaries (also reflected in the "Key protocol behaviors" section):

- Deposit → Hub: user approves and deposits a stable token; Hub normalizes value to USD6, computes shares using `pps6()`, and mints `USDzy` to the user.
- Withdraw queue: `requestWithdraw` burns `USDzy` and locks a USD liability; after ~2 hours a user can `claimWithdraw` which converts the locked USD liability to the requested asset and transfers it.
- Spoke borrow/repay: `Router` borrows from a `SpokeVault` (borrow role only); later the router or repay agent repays, reducing debt.
- Router rebalance → remote mint: when `needsRebalance()` is true, `Router` sends a message via an adapter; the destination `MessagingEndpointReceiver` verifies the message and forwards it to `USDzyRemoteMinter` which mints `USDzy` on the destination chain.


## Contract inventory

| File | Role / Responsibility | Upgradeable (UUPS) | Key Roles | Key functions | Pausable / ReentrancyGuard | Events | Notes |
|---|---|---:|---|---|---|---|---|
| `src/Hub.sol` | Arbitrum Hub vault: multi-asset deposits, withdraw queue, PPS | Yes | DEFAULT_ADMIN_ROLE, PAUSER_ROLE, KEEPER_ROLE | `deposit`, `requestWithdraw`, `claimWithdraw`, `pps6`, `setAssetConfig` | Pausable | `Deposit`, `WithdrawRequested`, `WithdrawClaimed` | Enforces asset haircuts, price staleness, USD6 normalization |
| `src/USDzy.sol` | USD-denominated yield share token (ERC20 UUPS + permit) | Yes | DEFAULT_ADMIN_ROLE, MINTER_ROLE, BURNER_ROLE | `mint`, `burn`, `permit`, `_authorizeUpgrade` | — | `Transfer`, `Approval`, `Mint`, `Burn` | Shares denominated in 6-decimal USD units; used by Hub and remote minters |
| `src/zpx/ZPXArb.sol` | Optional ZPX incentives token (UUPS + permit + burnFromWithPermit) | Yes | DEFAULT_ADMIN_ROLE, MINTER_ROLE | `mint`, `burn`, `burnFromWithPermit`, `_authorizeUpgrade` | — | `Transfer`, `Approval` | Designed for Arbitrum; integrated with `ZPXRewarder.sol` |
| `src/zpx/MintGate_Arb.sol` | Endpoint-pinned minter gate for ZPX on Arbitrum | No (Ownable gate) | owner (production: timelock) | `setEndpoint`, `consumeAndMint` | — | `EndpointSet`, `Minted` | Keeps a pinned endpoint and replay guard (`used[key]`) |
| `src/zpx/ZPXRewarder.sol` | Streaming/top-up rewarder for ZPX distributions | No | DEFAULT_ADMIN_ROLE, TOPUP_ROLE | `notifyTopUp` | ReentrancyGuard | `TopUpNotified` | Streams top-ups (accPerShare style) to reward recipients |
| `src/spoke/SpokeVault.sol` | Spoke (remote) vault; ERC-4626 surface but LP disabled; borrow/repay interface for Router | Yes | DEFAULT_ADMIN_ROLE, PAUSER_ROLE, BORROWER_ROLE | `borrow`, `repay`, `setBorrowCap`, `setMaxUtilizationBps`, `pause`/`unpause` | Pausable, ReentrancyGuard | `Borrowed`, `Repaid` | `deposit`/`mint`/`withdraw`/`redeem` revert with `LP_DISABLED()`; borrow cap and max utilization enforced |
| `src/router/Router.sol` | Routing & rebalancing: 7-day TVL ring buffer, rebalance decisions and adapter send | Yes | DEFAULT_ADMIN_ROLE, KEEPER_ROLE, FEE_COLLECTOR_ROLE | `pokeTvlSnapshot`, `avg7d`, `needsRebalance`, `rebalance`, `fill`, `repay` | Pausable, ReentrancyGuard | `RebalanceRequested`, `Filled`, `Repaid` | needsRebalance if TVL < 40% avg7d or 24h elapsed; sends messages via adapter |
| `src/messaging/MessagingEndpointReceiver.sol` | Adapter-authority receiver with replay protection and legacy fallback | No (library-style receiver) | DEFAULT_ADMIN_ROLE, RELAYER_ROLE | `setAdapter`, `setEndpoint`, `_verifyAndMark` (internal), `onMessage` (adapter calls) | — | `AdapterSet`, `EndpointSet`, `MessageReceived` | Adapter authorized by `setAdapter`; endpoints can be whitelisted; replay guard prevents double-minting |
| `src/usdzy/USDzyRemoteMinter.sol` | Remote minter that mints USDzy on cross-chain messages | Yes | DEFAULT_ADMIN_ROLE, RELAYER_ROLE, MINTER_ROLE | `onMessage` (calls `_verifyAndMark` then `IUSDzy.mint`), `_authorizeUpgrade` | — | `RemoteMinted` | Uses `MessagingEndpointReceiver` verification helper; has legacy path until adapter is set |
| `src/factory/Factory.sol` | Deploys ERC1967Proxy spoke & router instances, wires roles, pauses proxies and renounces bootstrap roles | Yes | DEFAULT_ADMIN_ROLE, PAUSER_ROLE | `setSpokeVaultImpl`, `setRouterImpl`, `deploySpoke`, `ImplementationUpdated` | — | `ProxyDeployed`, `ImplementationUpdated` | Proxies are paused-by-default after deployment; factory temporarily holds admin during bootstrap then transfers roles and renounces |


## Key protocol behaviors

### PPS & TVL

- `pps6()` (Hub) is the canonical price-per-share normalized to 6 decimals. The Hub computes USD-denominated liability using on-chain price feeds and the `pps6()` function for share conversions.
- All feeds are normalized to USD6 units when interacting with USDzy balances.
- Deposits apply an asset-specific `haircutBps` and enforce `maxStaleness` for feeds.

### Withdraw queue

- `requestWithdraw(asset, amount)` burns USDzy immediately and records a locked liability with a ready timestamp (≈2 hours). `claimWithdraw(asset)` can be executed after the ready time: the Hub converts the locked USD liability to the requested asset amount using the current feed and transfers the asset.
- `requestWithdraw` is allowed while contracts are paused; deposits and claims are paused.

### SpokeVault LP policy

- `src/spoke/SpokeVault.sol` exposes an ERC‑4626 surface but actively disables LP entry/exit: `deposit`, `mint`, `withdraw`, `redeem` revert with `LP_DISABLED()`.
- Only `borrow` and `repay` are enabled; borrow behavior is limited by `borrowCap` and `maxUtilizationBps`.

### Router health & rebalance

- `src/router/Router.sol` maintains a 7-day ring buffer of TVL snapshots via `pokeTvlSnapshot` and computes `avg7d()`.
- `needsRebalance()` returns true when TVL falls below 40% of `avg7d()` or 24h have elapsed since the last rebalance window.
- `rebalance()` triggers an adapter send; the adapter message is handled by `MessagingEndpointReceiver` and ultimately `USDzyRemoteMinter.onMessage` which mints USDzy on the destination chain if verification passes.

### Messaging & replay protection

- `src/messaging/MessagingEndpointReceiver.sol` enforces adapter-authority: `setAdapter(address)` pins the trusted adapter (or adapters) used to call `onMessage` entrypoints.
- Endpoints can be whitelisted via `setEndpoint(chainId, addr, allowed)`.
- `_verifyAndMark(srcChainId, srcAddr, payload, nonce)` performs signature/adapter checks and marks the nonce to prevent replays. `USDzyRemoteMinter.onMessage` calls this before `IUSDzy.mint`.

## Cross-chain Message Schema

The code expects a packed payload with the following field order and scaling:

```solidity
// Packed payload fields (document exact order & scaling)
struct BridgeMsg {
  uint64  srcChainId;
  address srcSender;
  address dstHub;        // Hub on destination chain
  address beneficiary;   // receiver of minted USDzy
  uint256 amount;        // scaling: USD6 units for USDzy amounts
  uint64  purpose;       // 1=rebal, 2=incentive, etc.
  uint64  nonce;
}
// Replay key (persisted in MessagingEndpointReceiver.used):
// keccak256(abi.encode(srcChainId, srcSender, nonce, beneficiary, amount, purpose))
```

Adapter-authority note: once `setAdapter(address)` is set on `MessagingEndpointReceiver.sol`, `onMessage` MUST be invoked by that adapter address and the `(srcChainId, srcAddr)` must be present in the `allowedEndpoint` map. Legacy direct calls are permitted only until an adapter is pinned; in production pin the adapter and require endpoints to be whitelisted and reject direct calls.

## Roles & Permissions Matrix

| Contract | Roles (holder post-deploy) | Capabilities |
|---|---|---|
| `src/Hub.sol` | DEFAULT_ADMIN, PAUSER (timelock/multisig); KEEPER (ops) | Set feeds/haircuts/staleness; pause/unpause; allow requestWithdraw during pause |
| `src/USDzy.sol` | MINTER/BURNER (Hub), DEFAULT_ADMIN (timelock/multisig) | UUPS upgrades; EIP-2612 permit; share mint/burn |
| `src/spoke/SpokeVault.sol` | DEFAULT_ADMIN/PAUSER (spoke admin), BORROWER (Router) | Borrow/repay; LP ops disabled (all ERC-4626 entrypoints revert) |
| `src/router/Router.sol` | DEFAULT_ADMIN/PAUSER (router admin), KEEPER/RELAYER (ops) | Fill, repay, poke snapshots, rebalance, setAdapter |
| `src/usdzy/USDzyRemoteMinter.sol` | owner (timelock/multisig) | Verified onMessage → mint USDzy |
| `src/zpx/ZPXArb.sol` | DEFAULT_ADMIN (timelock/multisig), MINTER (MintGate) | UUPS + permit + burn |
| `src/zpx/MintGate_Arb.sol` | owner (timelock/multisig) | Pin endpoint, replay-guarded mint |
| `src/zpx/ZPXRewarder.sol` | DEFAULT_ADMIN (timelock/multisig), TOPUP (MintGate) | Stream rewards to USDzy stakers |
| `src/factory/Factory.sol` | DEFAULT_ADMIN (governance) | Cache impls, deploy proxies (paused by default), wire roles, renounce temporary admin |

## Protocol Parameters & Defaults

### Hub (Arbitrum)

| Param | Default | Notes |
|---|---:|---|
| withdrawDelay | 2 hours | Queue delay before claims |
| maxStaleness | 300 seconds | Price freshness bound |
| haircutBps | USDC 10, USDT 15, DAI 10 | Safety haircut on deposits |
| pps6() | see formula | 1e6 scaling; 1_000_000 when supply==0 |

### Router

| Trigger | Value | Notes |
|---|---:|---|
| Health threshold | < 40% of 7-day avg TVL | Triggers rebalance |
| Time trigger | >= 24h since last | Triggers rebalance |

### SpokeVault

| Param | Default | Notes |
|---|---:|---|
| borrowCap | max (or env-configured) | Cap in asset units |
| maxUtilizationBps | 9000 | Utilization guardrail |

## Oracle integration

- The Hub supports DIA or Chainlink feeds; each asset config is set with `Hub.setAssetConfig(token, feed, tokenDecimals, priceDecimals, haircutBps, enabled)`.
- `maxStaleness` is enforced per-Hub and compared against feed timestamps; `haircutBps` is applied on deposit values and used to conservatively compute liability on withdraw.

### Feed Addresses

- Feeds are governed via `Hub.setAssetConfig(token, feed, tokenDecimals, priceDecimals, haircutBps, enabled)`.
- Example (mainnet USDC/USD Chainlink aggregator): `0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3`. Use via `setAssetConfig(token, feed, tokenDecs, priceDecs, haircutBps, enabled)`. Feeds are changeable by admin (timelock/multisig).

## Deployed Addresses

Fill addresses after production deploy. Tables intentionally left blank for auditor/ops to populate.

### Arbitrum (Hub)

| Contract | Address |
|---|---|
| Hub | |
| USDzy | |
| USDzyRemoteMinter | |
| ZPXArb | |
| MintGate_Arb | |
| ZPXRewarder | |

### Per-spoke chain

| Chain | SpokeVault | Router | Adapter |
|---|---|---|---|
|  |  |  |  |

## Deployment

### Prerequisites

- Foundry (forge/cast/anvil) installed: https://book.getfoundry.sh/
- An RPC endpoint and a funded deployer key.

### Environment variables (consolidated)

This table lists environment variables used by the deploy scripts in `script/` (Phase-1, Phase-1.5, Phase-2, and dry-run scripts).

| Variable | Used by script(s) | Purpose |
|---|---|---|
| `RPC_URL` | all scripts | RPC endpoint for forge script |
| `PRIVATE_KEY` | all scripts | Deployer private key for broadcast |
| `USDC_TOKEN` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | USDC token address (6 decimals) |
| `USDT_TOKEN` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | USDT token address (6 decimals) |
| `DAI_TOKEN` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | DAI token address |
| `DIA_USDC_FEED` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | DIA/Chainlink feed for USDC |
| `DIA_USDT_FEED` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | DIA/Chainlink feed for USDT |
| `DIA_DAI_FEED` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | DIA/Chainlink feed for DAI |
| `DIA_USDC_FEED_DECIMALS` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | Feed decimals for USDC feed (e.g. 8 or 18) |
| `DIA_USDT_FEED_DECIMALS` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | Feed decimals for USDT feed |
| `DIA_DAI_FEED_DECIMALS` | `script/Deploy_Phase1.s.sol`, `script/DryRun_Sepolia.s.sol` | Feed decimals for DAI feed |
| `TIMELOCK_ADMIN` | `script/Deploy_Phase1.s.sol` | (optional) Address that will be the Hub admin / timelock |
| `ZPX_ADMIN` | `script/Deploy_Phase1_5_Arb.s.sol` | Admin / owner for `ZPXArb.sol` |
| `USDZY_ADDR` | `script/Deploy_Phase1_5_Arb.s.sol` | Deployed `USDzy` address (Hub deploy output) |
| `USDZY_ADMIN` | `script/Deploy_Phase1_5_Arb.s.sol` | (optional) admin for USDzy; timelock recommended |
| `MINT_ENDPOINT_SRC_CHAINID` | `script/Deploy_Phase1_5_Arb.s.sol` | Source chain id for MintGate endpoint pinning |
| `MINT_ENDPOINT_SRC_ADDR` | `script/Deploy_Phase1_5_Arb.s.sol` | Source endpoint address for MintGate pinning |
| `ZPX_TOPUP_AMOUNT` | `script/Deploy_Phase1_5_Arb.s.sol` | Amount to top-up rewarder on deploy |
| `ZPX_TOPUP_DURATION` | `script/Deploy_Phase1_5_Arb.s.sol` | Duration (seconds) for streaming top-up |
| `FACTORY_ADDR` | `script/Deploy_Phase2_Spoke.s.sol` | Existing Factory to use for proxy deployment |
| `SPOKE_ASSET` | `script/Deploy_Phase2_Spoke.s.sol` | Asset token for the Spoke (e.g., USDC) |
| `SPOKE_ADMIN` | `script/Deploy_Phase2_Spoke.s.sol` | Admin for the deployed spoke proxy |
| `ROUTER_ADMIN` | `script/Deploy_Phase2_Spoke.s.sol` | Admin for router proxy |
| `ADAPTER_ADDR` | `script/Deploy_Phase2_Spoke.s.sol` | Adapter address used by Router to send messages |
| `FEE_COLLECTOR` | `script/Deploy_Phase2_Spoke.s.sol` | Fee collector address for Router |
| `KEEPER_ADDR` | `script/Deploy_Phase2_Spoke.s.sol` | Keeper address for scheduled `pokeTvlSnapshot` / rebalance |

### Core commands

```bash
forge build
forge test -vvv
forge snapshot
```

### Deploy commands (broadcast)

```bash
forge script script/Deploy_Phase1.s.sol --rpc-url $RPC_URL --broadcast
forge script script/Deploy_Phase1_5_Arb.s.sol --rpc-url $RPC_URL --broadcast
forge script script/Deploy_Phase2_Spoke.s.sol --rpc-url $RPC_URL --broadcast
forge script script/Deploy_MockAdapter.s.sol --rpc-url $RPC_URL --broadcast
forge script script/DryRun_Sepolia.s.sol --rpc-url $RPC_URL --broadcast
```

### Post-deploy assertions (what you should see)

- Admin roles held by a timelock/multisig (recommendation) for `DEFAULT_ADMIN_ROLE` on UUPS contracts.
- Deployed proxies (Factory) are paused-by-default; `PAUSER_ROLE` assigned and `BORROWER_ROLE` granted to Router where applicable.
- Adapter address set on `Router` and/or `MessagingEndpointReceiver` when wiring cross-chain mint paths.

## Testing & CI

### Run full tests

```bash
forge test -vvv
```

### Test suites

- Phase-1: `test/Hub_*`
- Phase-1.5: `test/zpx/*`
- Phase-2: `test/phase2/*`
- Upgrade simulations: `test/upgrade/*` (these assert storage layout compatibility)

### Gas snapshot

```bash
forge snapshot
```

### CI

- Formatting, build and tests are enforced in CI.
- Static analysis: `.github/workflows/*` contains a Slither CI workflow that runs Slither over `src/` and fails on Medium/High findings, and uploads `slither/slither.json` for triage.

## Security notes & audit briefs

Read the operational and audit documents:

- `docs/OPS_RUNBOOK.md`
- `docs/AUDIT_BRIEF_PHASE1.md`
- `docs/AUDIT_BRIEF.md`

### Key invariants and safeguards

- PPS correctness: `pps6()` must reflect total assets under management (after haircuts) / total USDzy supply (normalized to 6 decimals).
- Feed staleness: enforced via `maxStaleness` in `src/Hub.sol` — stale feeds cause operations to revert.
- Replay protection: `MessagingEndpointReceiver._verifyAndMark` prevents double-minting of remote messages.
- Borrow caps & utilization: `SpokeVault` enforces `borrowCap` and `maxUtilizationBps` to limit exposure.
- Reentrancy & CEI: critical state-changing flows use `nonReentrant` and follow checks-effects-interactions.

## Quick Ops Runbook

Short actionable commands; for full procedures see `docs/OPS_RUNBOOK.md`.

Rotate feeds (setAssetConfig)

```bash
# Example: set USDC feed and haircut via an admin (timelock)
forge script script/Deploy_Phase1.s.sol --rpc-url $RPC_URL --broadcast
# or use a custom script/cast transaction calling Hub.setAssetConfig
```

Change maxStaleness / haircutBps

```bash
# Use timelock to call Hub.setMaxStaleness(...) or Hub.setAssetConfig(...)
```

Pause/unpause Hub/Spoke/Router

```bash
# From admin / timelock
cast send <HUB_ADDRESS> "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
cast send <SPOKE_ADDRESS> "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
cast send <ROUTER_ADDRESS> "unpause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

Dry run scripts (Phase-1 and Phase-2)

```bash
forge script script/DryRun_Sepolia.s.sol --rpc-url $RPC_URL --broadcast
forge script script/Deploy_Phase2_Spoke.s.sol --rpc-url $RPC_URL --broadcast
```

## Upgrade notes & storage snapshots

- Storage layout snapshots are committed under `storage/*.json` and referenced by `test/upgrade/*` tests.
- All UUPS upgrades are expected to be governed by timelock/multisig; run `test/upgrade/*` before any production upgrade.

## Roadmap & versioning

- Current status: Phase-2 dev-complete (suggested tag: `v0.9.0-devcomplete`). Next steps: fuzzing, formal audit, production mainnet deploy.

## License & contact

- License: see repository top-level license files.
- Contact: repo maintainers; for security disclosures use the repository's GitHub security contact.

## References

- Contracts: paths listed throughout this README (see Contract inventory)
- Scripts: `script/Deploy_Phase1.s.sol`, `script/Deploy_Phase1_5_Arb.s.sol`, `script/Deploy_Phase2_Spoke.s.sol`, `script/Deploy_MockAdapter.s.sol`, `script/DryRun_Sepolia.s.sol`
- Tests: `test/**` (phase2 & upgrade sims included)
- Storage snapshots: `storage/*.json`
- CI: `.github/workflows/*`
