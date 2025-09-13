Ops Runbook — quick commands

Setup notes
- These commands assume you have a deployment EOA with private key loaded in env for Foundry scripts (e.g. `export PRIVATE_KEY=0x...`).

Rotate price feed (example for USDC on mainnet uses Chainlink 0x5083...4aD3)

```bash
# set asset config on Hub
# Hub.setAssetConfig(token, feed, tokenDecimals, priceDecimals, haircutBps, enabled)
forge script script/SetAssetConfig.s.sol --fork-url $RPC_URL --sig "setAssetConfig(address,address,uint8,uint8,uint16,bool)" --broadcast \
  --opt1
# example (replace addresses):
# Hub.setAssetConfig(USDC_ADDR, 0x5083...4aD3, 6, 8, 50, true)
```

Set staleness / haircut

```bash
# set max staleness (seconds)
# Hub.setMaxStaleness(seconds)
# example: set to 5 minutes
forge script script/SetMaxStaleness.s.sol --broadcast --rpc-url $RPC_URL --sig "setMaxStaleness(uint256)" --opt1

# set per-asset haircut via setAssetConfig (see above)
```

Pause / Unpause policy

- Hub: `pause()` disables deposit & claim flows; `requestWithdraw` remains allowed.
- Spokes/Router: `pause()` stops `fill`/`repay` operations.

Commands:

```bash
# pause hub
cast send $HUB_ADDRESS "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
# unpause hub
cast send $HUB_ADDRESS "unpause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# pause spoke
cast send $SPOKE_VAULT_ADDRESS "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
# unpause spoke
cast send $SPOKE_VAULT_ADDRESS "unpause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# pause router
cast send $ROUTER_ADDRESS "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
# unpause router
cast send $ROUTER_ADDRESS "unpause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

Withdraw queue servicing

```bash
# user flow
# 1) request withdraw (user)
forge script script/RequestWithdraw.s.sol --broadcast --rpc-url $RPC_URL --private-key $USER_KEY --sig "requestWithdraw(uint256)"
# 2) wait withdrawDelay (default 2 hours)
# 3) claim withdraw
forge script script/ClaimWithdraw.s.sol --broadcast --rpc-url $RPC_URL --private-key $USER_KEY --sig "claimWithdraw(uint256,address)"
```

Role handoff (EOA -> Timelock)

```bash
# grant role to timelock (as current admin)
# Example: transfer DEFAULT_ADMIN_ROLE on Hub to TIMELock
cast send $HUB_ADDRESS "grantRole(bytes32,address)" $(cast keccak256 "DEFAULT_ADMIN_ROLE") $TIMELOCK_ADDRESS --private-key $ADMIN_KEY --rpc-url $RPC_URL

# after validation, revoke from EOA
cast send $HUB_ADDRESS "revokeRole(bytes32,address)" $(cast keccak256 "DEFAULT_ADMIN_ROLE") $ADMIN_EOA --private-key $ADMIN_KEY --rpc-url $RPC_URL
```

Dry-run rehearsals

Phase-1 (Arbitrum Sepolia):
- Set USDC feed to Chainlink 0x5083...4aD3 (8 decimals) in env
- Run `forge script script/Deploy_Phase1.s.sol --broadcast` on Arbitrum Sepolia
- Deposit USDC via Hub.deposit(asset, amount)
- Request withdraw `requestWithdraw(shares)`
- Wait withdrawDelay (~2 hours) and `claimWithdraw(id, payoutAsset)`

Phase-1.5 (Arbitrum Sepolia):
- Run `forge script script/Deploy_Phase1_5_Arb.s.sol --broadcast`
- Top up ZPXRewarder via script
- Stake USDzy, let rewards accrue, call claim

Phase-2 (Base/Arb Sepolia):
- Deploy MockAdapter on both chains: `forge script script/Deploy_MockAdapter.s.sol --broadcast`
- Set endpoints on adapters and receivers
- Deploy spoke via `script/Deploy_Phase2_Spoke.s.sol --broadcast` on destination chain
- Set borrowCap / maxUtilization via `setBorrowCap` / `setMaxUtilizationBps`
- Optionally grant KEEPER
- Unpause vault and router
- Call Router.fill(to, amount) and verify user gets funds
- Call Router.repay(amount) and verify vault debt updated
- Trigger rebalance by setting health < 40% or advancing time +24h; verify adapter message emitted

Emergency back-out (fast path)

```bash
# 1) pause Hub and all Spokes/Routers
cast send $HUB_ADDRESS "pause()" --private-key $ADMIN_KEY
for v in $SPOKES; do cast send $v "pause()" --private-key $ADMIN_KEY; done
for r in $ROUTERS; do cast send $r "pause()" --private-key $ADMIN_KEY; done
# 2) service queued withdrawals by funds transfer or owner-run claims
# 3) resume operations when safe
```

Notes
- Replace script names and sigs with actual script files from `script/` directory. This runbook is a concise copy-paste reference; adapt addresses and env variables per network.
