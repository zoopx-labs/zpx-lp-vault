Audit Brief — Phase‑2 hub-and-spoke bridging (updated)

Overview
- Purpose: cross-chain hub & spokes for USDzy and LP vaults. Per-chain `SpokeVault` holds assets and supports borrow/repay; `Router` orchestrates fills/repays and rebalances via a MessagingAdapter. Factory deploys ERC1967Proxy proxies for SpokeVault/Router and wires roles.
- Upgradeability: UUPS pattern (OpenZeppelin UUPSUpgradeable) used across `SpokeVault`, `Router`, `Factory`, and `USDzyRemoteMinter`. Upgrade authorization is guarded by DEFAULT_ADMIN_ROLE or onlyOwner where applicable.
- Key protections: AccessControl for roles (DEFAULT_ADMIN_ROLE, PAUSER_ROLE, BORROWER_ROLE, KEEPER_ROLE, RELAYER_ROLE), Pausable, ReentrancyGuard, SafeERC20.

Trust boundaries (deltas)
- Adapter-authority model: `MessagingEndpointReceiver._verifyAndMark(...)` enforces that when an adapter is configured (`adapter != address(0)`), only the registered `adapter` contract may call `onMessage` entrypoints; `allowedEndpoint[srcChainId][srcAddr]` is still required. Legacy behavior (adapter==address(0)) allows direct calls from `srcAddr` for testing/fallback but should be avoided in production.
- Factory bootstrap & renounce: `Factory.deploySpoke` initializes proxies with the Factory as temporary admin to grant `BORROWER_ROLE` to the router and pause both proxies; after wiring, the Factory grants DEFAULT_ADMIN_ROLE & PAUSER_ROLE to provided admin/routerAdmin and renounces its own roles. Factory caches implementation addresses (`spokeVaultImpl`, `routerImpl`) and exposes `setSpokeVaultImpl`/`setRouterImpl` for admin rotation.

Important invariants (deltas)
- SpokeVault LP disabled: ERC4626 deposit/mint/withdraw/redeem functions are overridden and revert with `LP_DISABLED()`. Spoke flow uses borrow/repay paths instead of LP deposits.
- Factory paused-by-default: proxies deployed via Factory are paused immediately (`SpokeVault.pause()` and `Router.pause()` are called by Factory) — operator must transfer PAUSER_ROLE/DEFAULT_ADMIN_ROLE to admin and unpause.
- Messaging replay & adapter authority: `MessagingEndpointReceiver._verifyAndMark` builds keccak256 key over (srcChainId, srcAddr, payload, nonce) and stores it in `used` mapping; `USDzyRemoteMinter.onMessage` calls `_verifyAndMark` and then mints USDzy.
- Upgrade tests & storage: Upgrade-sim tests added under `test/upgrade/*` and storage snapshots committed under `storage/*.json` to validate storage layout compatibility.

Files of interest & locations (validate)
- `src/spoke/SpokeVault.sol` — ERC4626 shell; `initialize(asset,name,symbol,admin)`, `borrow(uint256,address)` (only BORROWER_ROLE), `repay(uint256)`, `setBorrowCap`, `setMaxUtilizationBps`, LP methods revert with `LP_DISABLED()`.
- `src/router/Router.sol` — `initialize(vault,adapter,admin,feeCollector)`, `pokeTvlSnapshot()`, `avg7d()`, `healthBps()`, `needsRebalance()`, `rebalance(uint64 dstChainId,address hubAddr)` only KEEPER_ROLE, `fill(address,uint256)` only RELAYER_ROLE, `repay(uint256)`.
- `src/messaging/MessagingEndpointReceiver.sol` — `setEndpoint`, `setAdapter`, `__MessagingEndpointReceiver_init`, `_verifyAndMark(srcChainId,srcAddr,payload,nonce)`.
- `src/usdzy/USDzyRemoteMinter.sol` — `initialize(usdzy,admin)`, `onMessage(srcChainId,srcAddr,payload,nonce)` calls `_verifyAndMark` then `IUSDzy(usdzy).mint`.
- `src/factory/Factory.sol` — `setSpokeVaultImpl`, `setRouterImpl`, `deploySpoke(...)` (deploys impls if missing, caches impls, deploys ERC1967Proxy, grants BORROWER_ROLE to router, pauses both, transfers admin/pauser, renounces Factory roles).
- tests: `test/phase2/*` and `test/upgrade/*` — SpokeVault borrow/repay, Router rebalance triggers, Messaging replay, Factory smoke, upgrade-sim tests.
- scripts: `script/Deploy_Phase2_Spoke.s.sol`, `script/Deploy_MockAdapter.s.sol`.

Attack surface summary (deltas)
- Adapter call surface: production receivers should have `adapter` set and rely on adapter authority — ensure `setAdapter` is only callable by admin and that adapter contract itself is secure.
- Factory bootstrap: because Factory is temporary admin during initialization, ensure scripts call `grantRole`/`renounceRole` sequences correctly and that Factory renounces all privileged roles at the end of `deploySpoke`.
- Paused proxies risk: proxies are paused by default; failure to properly transfer PAUSER_ROLE/DEFAULT_ADMIN_ROLE to a timelock/multisig blocks operations — include role transfer checks in deploy runbooks.

Suggested audit checklist (deltas)
1. Adapter-authority
   - Verify `MessagingEndpointReceiver.setAdapter` is onlyOwner and that `_verifyAndMark` correctly enforces `msg.sender == adapter` when adapter is set.
   - Validate `allowedEndpoint[srcChainId][srcAddr]` checks exist and are enforced for both legacy and adapter modes.
2. Factory bootstrap
   - Confirm `deploySpoke` calls `setSpokeVaultImpl`/`setRouterImpl` when impls are first created and that these setters emit `ImplementationUpdated` and require non-zero address.
   - Confirm Factory grants BORROWER_ROLE to router proxy and pauses both proxies before handing off admin and pauser roles to provided addresses, then renounces its own roles.
3. SpokeVault behavior
   - Confirm ERC4626 deposit/withdraw functions revert with `LP_DISABLED()` and that borrow/repay paths enforce `borrowCap` and `maxUtilizationBps`.
4. Upgrade simulations & storage
   - Validate `test/upgrade/*` upgrade‑sim tests and compare against `storage/*.json` snapshots for each UUPS contract.

Quick reproduction steps (Phase‑2)
1) Install Foundry and run `forge test --match-path test/phase2/* test/upgrade/* -vvv` to execute phase‑2 tests and upgrade sims.
2) Deploy mocks & spoke locally (use `script/Deploy_MockAdapter.s.sol` and `script/Deploy_Phase2_Spoke.s.sol`) with env vars: FACTORY_ADDR, SPOKE_ASSET, SPOKE_ADMIN, ROUTER_ADMIN, ADAPTER_ADDR, FEE_COLLECTOR, KEEPER_ADDR.

Deliverables & CI
- Storage snapshots: `storage/*.json` exist for Hub, USDzy, SpokeVault, Router, Factory, ZPXArb.
- Upgrade tests: `test/upgrade/*` are present.
- CI: `.github/workflows/slither-ci.yml` uploads `slither/slither.json` and fails on Medium/High findings.

Suggested immediate remediations (Phase‑2 deltas)
- Ensure deploy scripts assert role transfers (e.g., check `hasRole(DEFAULT_ADMIN_ROLE, admin)` after deploy) and log admin addresses to avoid accidental lock.
- Ensure `setAdapter` is onlyOwner and that adapter contract emits events for messages (audit adapter contract separately).

Contact
- Provide Slither JSON artifact for triage; I will map findings to specific functions and propose minimal, surgical code changes or suppressions.
