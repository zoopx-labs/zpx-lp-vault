here’s the final, phase-1 friendly plan that bakes in DIA price reads (no separate adapter contract), computes USD→USDzy via internal PPS, and already supports multiple stables in phase-1.

What ships in Phase-1 (Mainnet: Arbitrum Hub)
Contracts (Arbitrum)

USDzy.sol (upgradeable ERC-20 + Permit, non-rebasing “share” token)

Mint/Burn only by Hub.

No external oracle logic inside the token.

Hub.sol (upgradeable) — the brain

Accepts multiple stables (e.g., USDC/USDT/DAI) on Arbitrum.

Stores DIA feed addresses per asset and reads them on demand (no separate adapter).

Computes PPS internally:

pps6 = totalAssetsUSD6() / totalShares


Mint flow (per deposit):

usd6 = quoteUSD6(asset, amount) using DIA feed + haircut + staleness check

shares = usd6 * 1e6 / pps6 → USDzy.mint(user, shares)

Withdraw flow (2-hour delay you wanted):

requestWithdraw(shares) burns immediately; locks liability: usdOwed6 = shares * pps6 / 1e6

After readyAt = now + 2h, user calls claimWithdraw(ticketId, payoutAsset)

Hub converts usdOwed6 → amountOut = usdOwed6 * 1e6 / px6(payoutAsset) (DIA), pays if liquidity exists; else reverts until ops top up

DIA integration (direct reads in Hub)

mapping(address => address) diaFeed; // asset → DIA feed

mapping(address => uint8) assetDecs; // asset decimals

mapping(address => uint16) haircutBps; // safety haircut per asset

uint256 maxStaleness; // e.g., 5 minutes

quoteUSD6(asset, amount) reads IDIAFeed(feed).latestValue() (or DIA’s chain-specific ABI), checks staleness/decimals, applies haircut.

totalAssetsUSD6() (internal PPS input)

Sums all whitelisted asset balances on Hub, each normalized to USD6 via quoteUSD6(asset, balance) but with a special “internal mode” (no haircut / or separate haircuts if you prefer) to avoid compounding haircuts on both sides.

Later (phase-2), add confirmed spoke reports to this sum.

Withdraw Queue embedded (2h fixed delay), FIFO, with preferredPayoutAsset.

Admin/ops: add/remove assets, set feeds/decimals/haircuts, set maxStaleness, per-asset pause, per-epoch exit cap (optional).

Guards: ReentrancyGuard, Pausable, timelocked setters, role-gated.

ProxyAdmin + Transparent/UUPS Proxies (governed by timelocked multisig)

✅ That’s all you must deploy for the vault in phase-1.
(Optional now / later: ZPX reward stack below.)

Arbitrum ZPX Rewards (Optional at phase-1 launch; easy to add later)

ZPXArb.sol (uncapped ERC-20 + Permit) — Arbitrum ZPX

MintGate_Arb.sol — the only MINTER of ZPXArb; mints only on verified messages from Base

ZPXRewarder.sol — streams ZPXArb rewards per second to USDzy stakers (top-ups done epochically; no per-second messaging)

Base side (only if rewards/bridging go live now):
7) ZPXV1_Base.sol (you have it)
8) EmissionsManager_Base.sol — sequential mint→burn (net-zero) + message to Arbitrum to mint
9) BurnGate_Base.sol / MintGate_Base.sol — optional, for user bridges of ZPX
(Both sides use your chosen messaging layer; endpoints pinned; nonces tracked.)

Future Phase-2 (after audits — build/test now, deploy later)

SpokeVault.sol (ERC-4626 per chain × stable) — borrow/repay to support fast bridging

Router.sol (per chain) — calls SpokeVault borrow/repay; executes rebalancing

USDzyRemoteMinter/Burner.sol — mint/burn USDzy on other chains from Hub-authorized messages

MessagingAdapter_*.sol — verified cross-chain messages

Factory.sol — deploy SpokeVaults; register in Hub

Hub: key storage & functions (concise)
// Assets & DIA
struct AssetConfig {
  bool    enabled;
  address token;        // ERC20
  address feed;         // DIA feed
  uint8   decimals;     // token decimals
  uint16  haircutBps;   // e.g., 5 = 0.05%
}
mapping(address => AssetConfig) public assetCfg; // keyed by token address
uint256 public maxStaleness; // seconds

// DIA interface (stub actual DIA ABI for your network)
interface IDIAFeed { function latestValue() external view returns (int256 price, uint256 ts); }

// Normalize arbitrary asset to USD6 (for deposits/withdrawals)
function quoteUSD6(address asset, uint256 amount) public view returns (uint256 usd6);

// Internal PPS (USD per share, 6-dec)
function pps6() public view returns (uint256);

// Total assets in USD6 (Phase-1: sum of on-hub stable balances)
function totalAssetsUSD6() public view returns (uint256);

// Deposit (multi-asset)
function deposit(address asset, uint256 amount) external;

// Withdraw queue (2h delay)
function requestWithdraw(uint256 shares) external;
function claimWithdraw(uint256 ticketId, address payoutAsset) external;


Rounding policy (defensive):

Mint: round down shares to protect vault.

Withdraw: compute usdOwed6 with PPS, then convert to payoutAsset with DIA price rounding down the token amount paid; if you want pro-user bias, round up here (decide once and document).

Haircuts:

On mint (deposit): apply haircutBps to incoming asset to guard against slight de-peg/fees.

On withdraw: you can omit haircut (user-friendly) or apply symmetric haircuts. Most protocols apply small haircut only on deposit.

Staleness:

If DIA feed is stale, revert the operation (clear error message).

Optionally allow a peg fallback (1.0 with haircut) via an admin flag per asset; default off.

Phase-1 asset set (example)

USDC.e (Arbitrum) — feed = DIA_USDCUSD, decimals=6, haircutBps=0–10

USDT (Arbitrum) — feed = DIA_USDTUSD, decimals=6, haircutBps=10–25

DAI (Arbitrum) — feed = DIA_DAIUSD, decimals=18, haircutBps=5–15

Configure via timelocked setAssetConfig(token, feed, decimals, haircutBps, enabled).

How PPS is computed (internal & canonical)

Why internal? USDzy is a share of your own pool. PPS must be derived from your balances & liabilities, not an external TVL oracle.

Phase-1 formula:

totalAssetsUSD6() = Σ_over_enabled_assets quoteUSD6(asset, ERC20(asset).balanceOf(Hub)) 
                    (+ later: confirmed spoke balances)
pps6() = (totalAssetsUSD6 == 0 || totalShares == 0) 
         ? 1_000_000 
         : totalAssetsUSD6 * 1_000_000 / totalShares

Roles, safety, upgrade

Hub: DEFAULT_ADMIN_ROLE (timelocked multisig), KEEPER_ROLE (optional for auto-claims), PAUSER_ROLE.

USDzy: Minter/Burner = Hub only.

Setters under timelock: per-asset config, maxStaleness, haircut, enabling/disabling assets, withdraw delay.

Guards: ReentrancyGuard on deposit/withdraw/claim; Pausable on critical paths.

ProxyAdmin with timelock; _authorizeUpgrade bound to timelock.

Deployment plan (Phase-1)

Deploy ProxyAdmin & timelock.

Deploy USDzy (proxy) → set Hub as exclusive minter/burner.

Deploy Hub (proxy) → initialize with:

withdrawDelay = 2 hours

add USDC/USDT/DAI with DIA feed addresses, decimals, haircuts, enabled=true

set maxStaleness (e.g., 5 minutes)

Transfer admin to timelock; set PAUSER/KEEPER as needed.

(Optional) Deploy Arbitrum ZPXArb + MintGate_Arb + ZPXRewarder and Base EmissionsManager if you want ZPX incentives live now.

Invariants to keep in your tests

Shares invariant: sum(shareBalances) == USDzy.totalSupply().

PPS invariant: pps6 == totalAssetsUSD6 * 1e6 / totalShares (or returns 1e6 when supply=0).

Mint correctness: mintedShares <= usd6_in * 1e6 / pps6_before (round-down).

Withdraw correctness: liability frozen at request time (usdOwed6 stays constant); claim converts with current price of payoutAsset.

DIA staleness: stale price → revert (or peg fallback only when flag set).

Asset toggles: disabling an asset blocks new deposits/claims in that asset but does not brick existing tickets (you’ll service them via ops within 2h).

Pause: deposit & claim halt; requestWithdraw optionally allowed (your choice).

What you’ll build right now

USDzy.sol (upgradeable ERC-20 + Permit)

Hub.sol (with: multi-asset deposits, DIA reads inline, internal PPS, 2h queue, claim with payoutAsset)

ProxyAdmin/Timelock

(Optional now / later) ZPXArb, MintGate_Arb, ZPXRewarder, EmissionsManager_Base

This plan gives you multi-asset deposits in phase-1, uses DIA feeds directly from the Hub (no adapter), and guarantees USDzy price is always your internal PPS. When you’re ready for cross-chain, drop in spokes/routers without touching the Hub’s mint/withdraw math.

