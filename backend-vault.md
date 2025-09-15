# Backend Integration Blueprint: ZPX LP Vault

## Contract Inventory
| File | Contract | Chain Role | Key Public Funcs | Key Events | Roles Required | Upgradeability |
|------|----------|------------|------------------|------------|----------------|---------------|
| src/hub/Hub.sol | Hub | Hub | setAssetConfig, setWithdrawDelay, setMaxStaleness | AssetConfigSet, WithdrawDelaySet | DEFAULT_ADMIN | Proxy |
| src/usdzy/USDzy.sol | USDzy | ZPX | mint, burn, transfer | Transfer, Mint, Burn | DEFAULT_ADMIN | Proxy |
| src/spoke/SpokeVault.sol | SpokeVault | Spoke | borrow, repay, setBorrowCap, setMaxUtilizationBps, sendIdle | Borrowed, Repaid, IdleSent | DEFAULT_ADMIN, BORROWER | Proxy |
| src/router/Router.sol | Router | Router | fill, setProtocolFeeBps, setRelayerFeeBps, setFeeSplit, setFeeCollector, rebalance | FeeApplied, FillExecuted, RebalanceSuggested | DEFAULT_ADMIN, RELAYER, KEEPER | Proxy |
| src/messaging/MessagingEndpointReceiver.sol | MessagingEndpointReceiver | Adapter | receiveMessage | MessageReceived | DEFAULT_ADMIN | Proxy |
| src/usdzy/USDzyRemoteMinter.sol | USDzyRemoteMinter | Gateway | mintFromGateway, setGateway | MintFromGateway | DEFAULT_ADMIN, GATEWAY | Proxy |
| src/gateway/LocalDepositGateway.sol | LocalDepositGateway | Gateway | deposit, setDepositConfig | DepositReceived | DEFAULT_ADMIN | Proxy |
| src/policy/PolicyBeacon.sol | PolicyBeacon | Policy | post, setPolicyConfig | PolicyPosted | DEFAULT_ADMIN | Proxy |
| src/pps/PpsMirror.sol | PpsMirror | Policy | post | PpsPosted | DEFAULT_ADMIN | Proxy |
| src/usdzy/SharesAggregator.sol | SharesAggregator | ZPX | aggregateShares | SharesAggregated | DEFAULT_ADMIN | Proxy |
| src/factory/Factory.sol | Factory | ZPX | createVault, createRouter | VaultCreated, RouterCreated | DEFAULT_ADMIN | Proxy |
| src/arb/ZPXArb.sol | ZPXArb | ZPX | arbitrage | ArbitrageExecuted | DEFAULT_ADMIN | Proxy |
| src/gate/MintGate_Arb.sol | MintGate_Arb | Gateway | mintGate | MintGate | DEFAULT_ADMIN | Proxy |
| src/rewarder/ZPXRewarder.sol | ZPXRewarder | ZPX | reward | Rewarded | DEFAULT_ADMIN | Proxy |

## Event Catalog
| Event | Emitting Contract | When It Fires | Primary Keys / Correlation | Consumers |
|-------|-------------------|--------------|----------------------------|-----------|
| DepositReceived | LocalDepositGateway | User deposit | user, amount, asset | Deposit Gateway Runner, Indexer |
| MintFromGateway | USDzyRemoteMinter | Gateway mint | user, amount | Remote Minter Operator, Indexer |
| FeeApplied | Router | fill() called | user, protocolFee, relayerFee | Fee Accounting, Indexer |
| FillExecuted | Router | fill() called | user, amount | Flow Executor, Indexer |
| RebalanceSuggested | Router | rebalance() triggered | router, vault | Rebalancer, Indexer |
| Borrowed | SpokeVault | borrow() | user, amount | Rebalancer, Indexer |
| Repaid | SpokeVault | repay() | user, amount | Rebalancer, Indexer |
| IdleSent | SpokeVault | sendIdle() | admin, amount | Rebalancer, Indexer |
| PolicyPosted | PolicyBeacon | post() | router, policy | Policy Poster, Indexer |
| PpsPosted | PpsMirror | post() | router, pps | Policy Poster, Indexer |
| SharesAggregated | SharesAggregator | aggregateShares() | user, shares | Indexer |
| VaultCreated | Factory | createVault() | vault | Indexer |
| RouterCreated | Factory | createRouter() | router | Indexer |
| ArbitrageExecuted | ZPXArb | arbitrage() | asset, amount | Indexer |
| MintGate | MintGate_Arb | mintGate() | user, amount | Indexer |
| Rewarded | ZPXRewarder | reward() | user, amount | Indexer |
| MessageReceived | MessagingEndpointReceiver | receiveMessage() | srcChain, nonce | Indexer |

## Admin/API Calls to Automate
- Router.setProtocolFeeBps (DEFAULT_ADMIN): on fee change, bps, idempotency: chain+router+newBps
- Router.setRelayerFeeBps (DEFAULT_ADMIN): on relayer fee change, bps, idempotency: chain+router+newBps
- Router.setFeeSplit (DEFAULT_ADMIN): on fee split change, split, idempotency: chain+router+split
- Router.setFeeCollector (DEFAULT_ADMIN): on collector change, address, idempotency: chain+router+collector
- Hub.setAssetConfig (DEFAULT_ADMIN): on asset config change, config, idempotency: chain+hub+asset+config
- Hub.setWithdrawDelay (DEFAULT_ADMIN): on delay change, seconds, idempotency: chain+hub+delay
- Hub.setMaxStaleness (DEFAULT_ADMIN): on staleness change, seconds, idempotency: chain+hub+staleness
- SpokeVault.setBorrowCap (DEFAULT_ADMIN): on cap change, amount, idempotency: chain+vault+cap
- SpokeVault.setMaxUtilizationBps (DEFAULT_ADMIN): on utilization change, bps, idempotency: chain+vault+bps
- Router.rebalance (KEEPER): on policy trigger, no input, idempotency: chain+router+timestamp
- SpokeVault.borrow (BORROWER): on fill, amount, idempotency: chain+vault+user+amount+nonce
- SpokeVault.repay (BORROWER): on repay, amount, idempotency: chain+vault+user+amount+nonce
- LocalDepositGateway.deposit (DEFAULT_ADMIN): on deposit, user, amount, idempotency: chain+gateway+user+amount+nonce
- PolicyBeacon.post (DEFAULT_ADMIN): on policy post, router, policy, idempotency: chain+beacon+router+timestamp
- PpsMirror.post (DEFAULT_ADMIN): on pps post, router, pps, idempotency: chain+mirror+router+timestamp
- Role grants (DEFAULT_ADMIN): on onboarding, address, idempotency: chain+contract+role+address

## Bots/Services Needed
- **Policy Poster (hourly):** Trigger: timer; SLA: <5min. Posts MA7, coverage, state to PolicyBeacon/PpsMirror.
- **Rebalancer:** Trigger: PolicyPosted/RebalanceSuggested; SLA: <5min. Calls router.rebalance(), vault.repay(), orchestrates top-ups.
- **Flow-funded Executor:** Trigger: bridging request; SLA: <1min. Calls router.fill() on dest chain, ensures fee skimming.
- **Local Deposit Gateway Runner:** Trigger: user deposit; SLA: <1min. Quotes price, calls deposit.
- **USDzy Remote Minter Operator:** Trigger: mintFromGateway; SLA: <5min. Ensures gateway/adapter roles, indexes mints.
- **Fee Accounting:** Trigger: FeeApplied; SLA: <5min. Indexes fees, computes accruals.
- **Indexer:** Trigger: all events; SLA: <1min. Writes to DB, retries on failure.

## Data Model (Postgres DDL Sketch)
```sql
CREATE TABLE chains (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT UNIQUE NOT NULL,
  name TEXT,
  rpc_url TEXT,
  confirmations INT
);
CREATE TABLE assets (
  id SERIAL PRIMARY KEY,
  symbol TEXT,
  decimals INT,
  chain_id BIGINT REFERENCES chains(chain_id)
);
CREATE TABLE contracts (
  id SERIAL PRIMARY KEY,
  address TEXT UNIQUE NOT NULL,
  chain_id BIGINT REFERENCES chains(chain_id),
  type TEXT,
  name TEXT
);
CREATE TABLE roles (
  id SERIAL PRIMARY KEY,
  contract_id INT REFERENCES contracts(id),
  role TEXT,
  holder TEXT
);
CREATE TABLE tvl_snapshots (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  contract_id INT,
  tvl NUMERIC,
  timestamp TIMESTAMP,
  UNIQUE(chain_id, contract_id, timestamp)
);
CREATE TABLE ma7_snapshots (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  router_id INT,
  ma7 NUMERIC,
  timestamp TIMESTAMP,
  UNIQUE(chain_id, router_id, timestamp)
);
CREATE TABLE policy_advisories (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  router_id INT,
  state TEXT,
  coverage NUMERIC,
  timestamp TIMESTAMP,
  UNIQUE(chain_id, router_id, timestamp)
);
CREATE TABLE deposits (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  gateway_id INT,
  user TEXT,
  asset_id INT,
  amount NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE usdzy_mints (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  minter_id INT,
  user TEXT,
  amount NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE withdraw_requests (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  hub_id INT,
  user TEXT,
  asset_id INT,
  amount NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE withdraw_claims (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  hub_id INT,
  user TEXT,
  asset_id INT,
  amount NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE fills (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  router_id INT,
  user TEXT,
  amount NUMERIC,
  protocol_fee NUMERIC,
  relayer_fee NUMERIC,
  protocol_to_treasury NUMERIC,
  protocol_to_lps NUMERIC,
  net_to_user NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE repays (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  vault_id INT,
  user TEXT,
  amount NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE fee_applications (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  router_id INT,
  user TEXT,
  protocol_fee NUMERIC,
  relayer_fee NUMERIC,
  protocol_to_treasury NUMERIC,
  protocol_to_lps NUMERIC,
  net_to_user NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE topups (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  vault_id INT,
  amount NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE rebalances (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  router_id INT,
  vault_id INT,
  amount NUMERIC,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE router_health (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  router_id INT,
  status TEXT,
  timestamp TIMESTAMP,
  UNIQUE(chain_id, router_id, timestamp)
);
CREATE TABLE lnr_requests (
  id SERIAL PRIMARY KEY,
  chain_id BIGINT,
  adapter_id INT,
  src_chain BIGINT,
  dst_chain BIGINT,
  src_addr TEXT,
  dst_addr TEXT,
  payload_hash TEXT,
  nonce BIGINT,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
CREATE TABLE messages (
  id SERIAL PRIMARY KEY,
  adapter_id INT,
  src_chain BIGINT,
  dst_chain BIGINT,
  src_addr TEXT,
  dst_addr TEXT,
  payload_hash TEXT,
  nonce BIGINT,
  replay_key TEXT,
  timestamp TIMESTAMP,
  idempotency_key TEXT UNIQUE
);
```

## Config Schema (YAML)
```yaml
chains:
  - name: arbitrum
    chainId: 42161
    rpc: https://arb1.example.com
    confirmations: 12
  - name: optimism
    chainId: 10
    rpc: https://op.example.com
    confirmations: 12
contracts:
  arbitrum:
    hub: "0x..."
    usdzy: "0x..."
    spokeVaults:
      - "0x..."
    routers:
      - "0x..."
    gateways:
      - "0x..."
    beacons:
      - "0x..."
roles:
  arbitrum:
    DEFAULT_ADMIN: "0x..."
    PAUSER: "0x..."
    KEEPER: "0x..."
    BORROWER: "0x..."
    RELAYER: "0x..."
    TOPUP: "0x..."
fees:
  arbitrum:
    protocolFeeBps: 5
    relayerFeeBps: 20
    split: [2500, 7500]
    collector: "0x..."
oracles:
  arbitrum:
    - address: "0x..."
      decimals: 8
      staleness: 300
policyThresholds:
  EMERGENCY:
    bps: 95000
    timing: 60
  OK:
    bps: 65000
    timing: 3600
  DRAIN:
    bps: 99000
    timing: 30
```

## External Dependencies & Sample I/O
- **Oracle sources:** DIA/Chainlink; sample read: `AggregatorV3Interface.latestRoundData()`; staleness: compare `block.timestamp - updatedAt`.
- **Messaging adapters:** MessagingEndpointReceiver; payload: `{srcChain, dstChain, nonce, payloadHash}`.
- **Off-chain PPS calculation:** Policy Poster computes MA7, coverage, posts to PolicyBeacon/PpsMirror.

## Gaps & Risks
- Some contracts may lack granular events for all state changes (e.g., missing withdraw claim events).
- Fee math edge cases: rounding, protocol/LP split, multi-chain accruals.
- Role/ownership handoff: ensure all admin/keeper/relayer roles are indexed and rotated securely.
- Upgradeability: proxy patterns must be indexed and tracked for admin changes.
- Idempotency: ensure all off-chain writes use idempotency keys to avoid double-processing.

## Microservice Map & Minimal Runbook
### Microservice Map
- **Policy Poster:** Depends on DB, PolicyBeacon, PpsMirror; triggers: timer; topics: policy.post, pps.post; tables: ma7_snapshots, policy_advisories.
- **Rebalancer:** Depends on DB, Router, SpokeVault; triggers: policy events; topics: router.rebalance, vault.repay; tables: rebalances, repays, router_health.
- **Flow Executor:** Depends on DB, Router; triggers: fill requests; topics: router.fill; tables: fills, fee_applications.
- **Deposit Gateway Runner:** Depends on DB, LocalDepositGateway; triggers: deposit events; topics: deposit; tables: deposits.
- **Remote Minter Operator:** Depends on DB, USDzyRemoteMinter; triggers: mint events; topics: mintFromGateway; tables: usdzy_mints.
- **Fee Accounting:** Depends on DB; triggers: FeeApplied; tables: fee_applications.
- **Indexer:** Depends on all contracts; triggers: all events; tables: all above.

### Minimal Runbook
1. Start DB and event indexer (env: DB_URL, chain RPCs)
2. Start Policy Poster (env: DB_URL, beacon/mirror addresses)
3. Start Rebalancer (env: DB_URL, router/vault addresses)
4. Start Flow Executor (env: DB_URL, router addresses)
5. Start Deposit Gateway Runner (env: DB_URL, gateway addresses)
6. Start Remote Minter Operator (env: DB_URL, minter/gateway addresses)
7. Start Fee Accounting (env: DB_URL)
8. Health checks: each service exposes `/healthz` endpoint; monitor event lag, DB writes, contract call success
9. Env vars: DB_URL, chain RPCs, contract addresses, admin keys, role configs

---
This blueprint covers backend integration for ZPX LP Vault, including contract inventory, event catalog, admin calls, bots/services, data models, configs, dependencies, risks, and a microservice map/runbook.
