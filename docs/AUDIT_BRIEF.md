Audit Brief — Phase‑2 hub-and-spoke bridging

Overview
- Purpose: cross-chain hub & spokes for USDzy and LP vaults. Per-chain SpokeVault holds assets and supports borrow/repay; Router orchestrates fills/repays and rebalances via MessagingAdapter.
- Upgradeability: UUPS pattern (OpenZeppelin UUPSUpgradeable) used across Hub, SpokeVault, Router, Factory, USDzyRemoteMinter.
- Key protections: AccessControl for roles (DEFAULT_ADMIN_ROLE, PAUSER_ROLE, BORROWER_ROLE, KEEPER_ROLE, RELAYER_ROLE), Pausable, ReentrancyGuard, SafeERC20.

Trust boundaries
- Adapter authority: MessagingEndpointReceiver enforces adapter address; only messages from the registered adapter are accepted once set. Legacy fallback remains until adapter is configured.
- Factory: temporarily becomes admin during proxy bootstrap; later renounces roles and transfers admin to provided admin addresses.

Important invariants
- ERC4626 share invariants: totalAssets() and totalSupply() must remain consistent; deposits/withdraws are restricted (LP entry disabled in SpokeVault by default) and borrow/repay adjust debt accounting.
- Debt bounds: borrow cap and utilization BPS must be enforced and tested to prevent over-borrowing.
- Replay protection: MessagingEndpointReceiver maintains a nonce/map of processed messages to prevent replay.
- Storage layout: UUPS upgrades require careful storage layout compatibility; storage snapshots are committed under `storage/*.json`.

Files of interest & locations
- Contracts: `src/spoke/SpokeVault.sol`, `src/router/Router.sol`, `src/messaging/MessagingEndpointReceiver.sol`, `src/messaging/MockAdapter.sol`, `src/usdzy/USDzyRemoteMinter.sol`, `src/factory/Factory.sol`.
- Tests: `test/phase2/*` and `test/upgrade/*` contain functional and upgrade-sim tests.
- Storage snapshots: `storage/Hub.json`, `storage/SpokeVault.json`, `storage/Router.json`, `storage/USDzy.json`, `storage/ZPXArb.json`, `storage/Factory.json`.
- CI: `.github/workflows/slither-ci.yml` runs Slither on `src/` and uploads `slither/slither.json`.

Attack surface summary
- External calls: Adapter -> Receiver (onMessage), Router -> Adapter (send), Token transfers via SafeERC20. Ensure external adapter cannot call arbitrary functions on contracts except `onMessage` entrypoint.
- Upgrade pathways: UUPS `upgradeTo` guarded by DEFAULT_ADMIN_ROLE; ensure timelock or multisig holds admin in production.
- Factory bootstrapping: Factory is a transient admin; ensure role renounces are correct and atomic in deployment scripts.

Suggested audit checklist
- AccessControl review: Confirm only intended roles can call sensitive functions. Verify renounce patterns in Factory deploySpoke.
- Adapter authorization: Ensure `setAdapter` can only be called by admin and that legacy fallback is well-documented; confirm no path where arbitrary caller can impersonate adapter once set.
- Message replay: Confirm nonce/processed-message mapping prevents replay across remote chains and persists in storage.
- Reentrancy: Inspect public/external functions modifying balances and external calls; ensure CEI pattern and reentrancy guards where needed.
- Storage layout: Validate storage layouts in `storage/*.json` and confirm upgrade tests cover field additions/ordering.
- Slither + static analysis: Run Slither on `src/` (CI workflow does this). Triage any Medium/High findings.
- Fuzzing: Add fuzz tests around borrow/repay, utilization, caps, and Router rebalance decisions.
- Gas: Identify hot loops (e.g., ring buffer scans) and gas cost for rebalances; confirm limits and off-chain gas estimates.

Quick reproduction steps for auditors
1) Checkout branch: `ci/slither-fail-on-medium` (or main branch if merged).
2) Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup`
3) Run tests: `forge test -vvv`
4) Run Slither (CI): Use the GitHub Actions run that outputs `slither/slither.json` or run locally via docker:
   - `docker run --rm -v $(pwd):/tmp -w /tmp --entrypoint slither ghcr.io/crytic/slither:latest src/ --json -o slither/slither.json`
   - If Docker not available, use a Linux host or CI runner.

Deliverables
- Storage snapshots: `storage/*.json` (already committed).
- Upgrade-sim tests: `test/upgrade/*` (already present).
- Slither CI artifact: `.github/workflows/slither-ci.yml` uploads `slither/slither.json` for triage.

Suggested immediate remediations (if Medium/High Slither findings appear)
- Fix reentrancy or unchecked external-call patterns by adding nonReentrant modifiers or reordering logic to follow CEI.
- Limit external adapter calls surface by adding a single-entrypoint and strict checks on message payload lengths, expected sender chain IDs, and message nonces.
- Add explicit storage gap patterns where new storage might be inserted between versions (UUPS + OZ gap patterns already used; verify each contract includes correct `uint256[50] private __gap;`).

Contact
- For follow-up triage, provide the Slither JSON artifact or allow me to fetch CI artifact; I can create a triage report mapping findings to code and suggested fixes.
