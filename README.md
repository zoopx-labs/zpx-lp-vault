
# ZoopX Protocol - liquidity Pool Vaults


This repository is a Foundry monorepo implementing a production-oriented cross-chain hub-and-spoke liquidity vault built by ZoopX Labs. It provides a multi-asset Arbitrum Hub with a USD-denominated yield-share token (`USDzy`), optional ZPX incentives, and Phase‑2 spoke vaults with routing to balance liquidity across chains via adapters and a Factory deployer.

Key properties: UUPS upgradeability, role-gated admin surfaces (OpenZeppelin AccessControl), pausability, SafeERC20 usage, and explicit replay protection for cross-chain messages.

## Table of contents

- Architecture at a glance
- Diagram (flows)
- Contract inventory
- Key protocol behaviors
- Deployment
- Testing & CI
- Security, upgradeability & storage
- Operational runbook quicklinks
- Roadmap & versioning
- License & contact

## Architecture at a glance

Phase-1 → Phase-1.5 → Phase-2

- Phase-1 (Arbitrum Hub): `src/Hub.sol` + `src/USDzy.sol` — multi-asset deposits (USDC/USDT/DAI), price feeds, canonical PPS (`pps6()`) and a 2-hour withdraw queue.
- Phase-1.5 (ZPX incentives): `src/zpx/ZPXArb.sol`, `src/zpx/MintGate_Arb.sol`, `src/zpx/ZPXRewarder.sol` — optional ZPX token, endpoint-pinned minter and streaming/top-up rewarder.
- Phase-2 (Spokes/Router/Messaging/Factory): `src/spoke/SpokeVault.sol`, `src/router/Router.sol`, `src/messaging/MessagingEndpointReceiver.sol`, `src/usdzy/USDzyRemoteMinter.sol`, `src/factory/Factory.sol`, `src/messaging/MockAdapter.sol` — spoke vaults (ERC-4626 surface with LP disabled), router TVL ring buffer and rebalance, adapter → receiver mint, and a Factory to deploy and wire proxies.

## Diagram (flows)

Deposit → Mint

```
User --deposit(asset)--> Hub (`src/Hub.sol`) --mint--> USDzy (`src/USDzy.sol`) (pps6() based)
```

Withdraw queue

```
User --requestWithdraw(asset, amount)--> Hub (burn USDzy, lock USD liability) --after 2h--> claimWithdraw(asset) --> Hub transfers asset
```

Borrow / Repay (Spoke)

```
Router --borrow--> SpokeVault (`src/spoke/SpokeVault.sol`) --repay--> Router/Hub
```

Router Rebalance

```
Router (`src/router/Router.sol`) --needsRebalance()--> adapter.send(...) --> MessagingEndpointReceiver (`src/messaging/MessagingEndpointReceiver.sol`) --onMessage--> USDzyRemoteMinter (`src/usdzy/USDzyRemoteMinter.sol`) mint
```

Adapter → Receiver → Mint

```
Adapter (`src/messaging/MockAdapter.sol` or production adapter) -> MessagingEndpointReceiver -> USDzyRemoteMinter.onMessage -> IUSDzy.mint
```

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

### Oracle integration

- The Hub supports DIA or Chainlink feeds; each asset config is set with `Hub.setAssetConfig(token, feed, tokenDecimals, priceDecimals, haircutBps, enabled)`.
- `maxStaleness` is enforced per-Hub and compared against feed timestamps; `haircutBps` is applied on deposit values and used to conservatively compute liability on withdraw.

## Upgradeability & storage

- Major contracts use UUPS: `src/Hub.sol`, `src/USDzy.sol`, `src/spoke/SpokeVault.sol`, `src/router/Router.sol`, `src/usdzy/USDzyRemoteMinter.sol`, `src/factory/Factory.sol`, `src/zpx/ZPXArb.sol`.
- Authorization for upgrades is implemented in `_authorizeUpgrade` and gated by admin roles.
- Storage layout snapshots are committed under `storage/*.json`. Run the upgrade-sim tests in `test/upgrade/*` to validate storage compatibility before upgrades.

## Deployment

### Prerequisites

- Foundry (forge/cast/anvil) installed: https://book.getfoundry.sh/
- An RPC endpoint and a funded deployer key.

### Environment variables by script

#### Phase-1 (`script/Deploy_Phase1.s.sol`)

| Variable | Purpose |
|---|---|
| `USDC_TOKEN` | USDC token address (6 decimals) |
| `USDT_TOKEN` | USDT token address (6 decimals) |
| `DAI_TOKEN` | DAI token address |
| `DIA_USDC_FEED` | DIA/Chainlink feed for USDC |
| `DIA_USDT_FEED` | DIA/Chainlink feed for USDT |
| `DIA_DAI_FEED` | DIA/Chainlink feed for DAI |
| `DIA_USDC_FEED_DECIMALS` | Feed decimals for USDC feed (e.g. 8 or 18) |
| `DIA_USDT_FEED_DECIMALS` | Feed decimals for USDT feed |
| `DIA_DAI_FEED_DECIMALS` | Feed decimals for DAI feed |
| `TIMELOCK_ADMIN` | (optional) Address that will be the Hub admin / timelock |
| `RPC_URL` | RPC endpoint for forge script |
| `PRIVATE_KEY` | Deployer private key for broadcast |

#### Phase-1.5 (`script/Deploy_Phase1_5_Arb.s.sol`)

| Variable | Purpose |
|---|---|
| `ZPX_ADMIN` | Admin / owner for `ZPXArb.sol` |
| `USDZY_ADDR` | Deployed `USDzy` address (Hub deploy output) |
| `USDZY_ADMIN` | (optional) admin for USDzy; timelock recommended |
| `MINT_ENDPOINT_SRC_CHAINID` | Source chain id for MintGate endpoint pinning |
| `MINT_ENDPOINT_SRC_ADDR` | Source endpoint address for MintGate pinning |
| `ZPX_TOPUP_AMOUNT` | Amount to top-up rewarder on deploy |
| `ZPX_TOPUP_DURATION` | Duration (seconds) for streaming top-up |

#### Phase-2 (`script/Deploy_Phase2_Spoke.s.sol`, `script/Deploy_MockAdapter.s.sol`)

| Variable | Purpose |
|---|---|
| `FACTORY_ADDR` | Existing Factory to use for proxy deployment |
| `SPOKE_ASSET` | Asset token for the Spoke (e.g., USDC) |
| `SPOKE_ADMIN` | Admin for the deployed spoke proxy |
| `ROUTER_ADMIN` | Admin for router proxy |
| `ADAPTER_ADDR` | Adapter address used by Router to send messages |
| `FEE_COLLECTOR` | Fee collector address for Router |
| `KEEPER_ADDR` | Keeper address for scheduled `pokeTvlSnapshot` / rebalance |

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

## Operational runbook quicklinks

- Rotate feeds / haircuts / maxStaleness: `src/Hub.sol` setters (call via timelock)
- Pause / unpause: `src/Hub.sol`, `src/spoke/SpokeVault.sol`, `src/router/Router.sol`
- Service withdraw queue: `requestWithdraw` / `claimWithdraw` in `src/Hub.sol`
- Reward top-ups: `src/zpx/ZPXRewarder.sol::notifyTopUp`

## Upgrade notes


## Roadmap & versioning

Documentation version: 1.0

## License & contact
- Maintained by: ZoopX Labs — https://github.com/zoopx-labs
- Security disclosures: Please use the repository's GitHub security contact and responsible disclosure process.

For general inquiries or partnership requests, contact maintainers via the GitHub repo or email security@zoopx.xyz (preferred for security reports).

## References

- Contracts: paths listed throughout this README (see Contract inventory)
- Scripts: `script/Deploy_Phase1.s.sol`, `script/Deploy_Phase1_5_Arb.s.sol`, `script/Deploy_Phase2_Spoke.s.sol`, `script/Deploy_MockAdapter.s.sol`, `script/DryRun_Sepolia.s.sol`
- Tests: `test/**` (phase2 & upgrade sims included)
- Storage snapshots: `storage/*.json`
- CI: `.github/workflows/*`

---

© 2025 ZoopX Labs. Maintained by ZoopX Labs — https://github.com/zoopx-labs

For security disclosures: support@zoopx.xyz

Built with Foundry (forge). This documentation is maintained for developer and auditor use; confirm on-chain addresses and admin roles before interacting with deployed contracts.




