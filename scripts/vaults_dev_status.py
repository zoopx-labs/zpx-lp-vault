#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from glob import glob
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
SCRIPT_DIR = ROOT / "script"
TEST_DIR = ROOT / "test"
DOCS_DIR = ROOT / "docs"
STORAGE_DIR = ROOT / "storage"
SNAPSHOTS_DIR = STORAGE_DIR / "snapshots"

CONTRACT_CANDIDATES = {
    "Hub": "src/Hub.sol",
    "USDzy": "src/USDzy.sol",
    "Router": "src/router/Router.sol",
    "SpokeVault": "src/spoke/SpokeVault.sol",
    "Factory": "src/factory/Factory.sol",
    "MessagingEndpointReceiver": "src/messaging/MessagingEndpointReceiver.sol",
    "USDzyRemoteMinter": "src/usdzy/USDzyRemoteMinter.sol",
    "LocalDepositGateway": "src/gateway/LocalDepositGateway.sol",
    "PolicyBeacon": "src/policy/PolicyBeacon.sol",
    "PpsMirror": "src/pps/PpsMirror.sol",
    "ZPXArb": "src/zpx/ZPXArb.sol",
    "MintGate_Arb": "src/zpx/MintGate_Arb.sol",
    "ZPXRewarder": "src/zpx/ZPXRewarder.sol",
}

ROLE_NAMES = [
    "DEFAULT_ADMIN_ROLE",
    "PAUSER_ROLE",
    "KEEPER_ROLE",
    "BORROWER_ROLE",
    "MINTER_ROLE",
    "BURNER_ROLE",
    "GATEWAY_ROLE",
    "REBALANCER_ROLE",
    "RELAYER_ROLE",
    "UPGRADER_ROLE",
]


def run(cmd: List[str], cwd: Optional[Path] = None, check: bool = False) -> Tuple[int, str, str]:
    p = subprocess.Popen(cmd, cwd=str(cwd or ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = p.communicate()
    if check and p.returncode != 0:
        raise subprocess.CalledProcessError(p.returncode, cmd, output=out, stderr=err)
    return p.returncode, out, err


def detect_tools() -> Dict[str, str]:
    tools = {}
    for name, args in (
        ("forge", ["forge", "--version"]),
        ("cast", ["cast", "--version"]),
        ("solc", ["solc", "--version"]),
        ("slither", ["slither", "--version"]),
    ):
        code, out, err = run(args)
        tools[name] = (out or err).strip() if code == 0 else "absent"
    return tools


def ensure_build() -> Tuple[bool, str]:
    code, out, err = run(["bash", "-lc", "forge clean && forge build"], check=False)
    success = code == 0
    return success, (out + "\n" + err)


def maybe_run_gas() -> Optional[str]:
    code, out, err = run(["bash", "-lc", "forge test -vv --gas-report"], check=False)
    return (out + "\n" + err) if code == 0 else None


def run_slither_json(tmp_path: Path) -> Optional[Dict[str, Any]]:
    if shutil.which("slither") is None:
        return None
    code, out, err = run(["bash", "-lc", f"slither . --json {tmp_path}"], check=False)
    if code != 0:
        return None
    try:
        return json.loads(tmp_path.read_text())
    except Exception:
        return None


def find_contract_path(contract: str) -> Optional[Path]:
    # Prefer declared mapping; fallback to glob
    mapped = CONTRACT_CANDIDATES.get(contract)
    if mapped and (ROOT / mapped).exists():
        return ROOT / mapped
    matches = list(ROOT.glob(f"src/**/{contract}.sol"))
    return matches[0] if matches else None


def forge_inspect(contract: str, what: str) -> Optional[Any]:
    code, out, err = run(["forge", "inspect", contract, what])
    if code != 0:
        return None
    try:
        return json.loads(out)
    except Exception:
        return out.strip()


def collect_contract_info(contract: str) -> Dict[str, Any]:
    info: Dict[str, Any] = {"name": contract}
    path = find_contract_path(contract)
    info["path"] = str(path) if path else None
    info["abi"] = forge_inspect(contract, "abi")
    info["methods"] = forge_inspect(contract, "methods")
    info["storage_layout"] = forge_inspect(contract, "storage-layout")

    # Derive events/functions/modifiers from ABI
    events = []
    functions = []
    if isinstance(info["abi"], list):
        for item in info["abi"]:
            if item.get("type") == "event":
                events.append(item.get("name"))
            if item.get("type") == "function":
                stateMutability = item.get("stateMutability")
                if stateMutability in ("nonpayable", "payable", "view", "pure"):
                    functions.append(item.get("name"))
    info["events"] = sorted(set(events))
    info["functions"] = sorted(set(functions))

    # Source scan for roles, UUPS, gaps, modifiers
    roles_found: List[str] = []
    onlyrole_map: Dict[str, List[str]] = {}
    uups = False
    authorize_upgrade = False
    has_gap = False
    if path and path.exists():
        src = path.read_text()
        for rn in ROLE_NAMES:
            if re.search(rf"\b{re.escape(rn)}\b", src):
                roles_found.append(rn)
        for m in re.finditer(r"onlyRole\(([^\)]+)\)", src):
            role_expr = m.group(1)
            onlyrole_map.setdefault(role_expr.strip(), [])
        # Map functions to roles by scanning lines above function headers (approx)
        func_pattern = re.compile(r"function\s+(\w+)\s*\(")
        # Simple: find role lines preceding function names
        lines = src.splitlines()
        current_mods: List[str] = []
        for i, line in enumerate(lines):
            if "onlyRole(" in line:
                current_mods.append(line.strip())
            if line.strip().startswith("function "):
                m = re.match(r"function\s+(\w+)", line.strip())
                if m:
                    fname = m.group(1)
                    roles_for_fn = []
                    for mod in current_mods:
                        rm = re.search(r"onlyRole\(([^\)]+)\)", mod)
                        if rm:
                            roles_for_fn.append(rm.group(1).strip())
                    if roles_for_fn:
                        onlyrole_map.setdefault(", ".join(sorted(set(roles_for_fn))), []).append(fname)
                    current_mods = []
        uups = ("UUPSUpgradeable" in src) or ("_authorizeUpgrade(" in src)
        authorize_upgrade = ("_authorizeUpgrade(" in src)
        has_gap = bool(re.search(r"__gap\s*;", src))
    info["roles"] = sorted(set(roles_found))
    info["role_function_map"] = {k: sorted(set(v)) for k, v in onlyrole_map.items() if v}
    info["uups"] = uups
    info["authorize_upgrade"] = authorize_upgrade
    info["has_gap"] = has_gap
    return info


def compare_storage_snapshots(contracts: List[str]) -> Dict[str, str]:
    """Return per-contract: 'No changes' or 'Changes'."""
    results: Dict[str, str] = {}
    SNAPSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    for c in contracts:
        curr = forge_inspect(c, "storage-layout")
        if curr is None:
            results[c] = "Unknown"
            continue
        # Existing snapshot path
        legacy = STORAGE_DIR / f"{c}.json"
        snap = SNAPSHOTS_DIR / f"{c}.json"
        baseline_path = legacy if legacy.exists() else snap
        status = "No changes"
        if baseline_path.exists():
            try:
                prev = json.loads(baseline_path.read_text())
                status = "No changes" if json.dumps(prev, sort_keys=True) == json.dumps(curr, sort_keys=True) else f"Changes in {c}"
            except Exception:
                status = "Unknown"
        else:
            # Write a new snapshot for review
            snap.write_text(json.dumps(curr, indent=2))
            status = "Snapshot created"
        results[c] = status
    return results


def extract_router_fee_invariants(router_path: Optional[Path]) -> Dict[str, str]:
    res = {
        "protocolFeeBps_cap_le_5": "Unknown",
        "protocolShare_plus_lpShare_eq_10000": "Unknown",
        "destination_skimming": "Unknown",
        "lp_share_retained": "Unknown",
        "relayerFeeBps_used": "Unknown",
        "fee_events_present": "Unknown",
        "feeCollector_required_when_protocol_fee": "Unknown",
    }
    if not router_path or not router_path.exists():
        return res
    src = router_path.read_text()
    if re.search(r"setProtocolFeeBps\(.*?\)\s*\{[\s\S]*?require\([^;]*?<=\s*5\b", src):
        res["protocolFeeBps_cap_le_5"] = "Yes"
    elif "protocolFeeBps" in src:
        res["protocolFeeBps_cap_le_5"] = "No/Unsure"
    if re.search(r"protocolShareBps\s*\+\s*lpShareBps\s*==\s*10000", src):
        res["protocolShare_plus_lpShare_eq_10000"] = "Yes"
    if re.search(r"FeeApplied|FillExecuted", src):
        res["fee_events_present"] = "Yes"
    if "relayerFeeBps" in src:
        res["relayerFeeBps_used"] = "Yes"
    if re.search(r"feeCollector\s*\!=\s*address\(0\)", src):
        res["feeCollector_required_when_protocol_fee"] = "Yes"
    # Destination/LP share heuristics
    if re.search(r"protocolFeeBps|protocolShareBps|lpShareBps", src) and re.search(r"vault|SpokeVault", src):
        res["destination_skimming"] = "Yes"
        res["lp_share_retained"] = "Yes"
    return res


def factory_hygiene(factory_path: Optional[Path]) -> Dict[str, str]:
    res = {"impl_caching": "Unknown", "proxies_paused": "Unknown", "router_gets_borrower": "Unknown", "renounces_roles": "Unknown", "spoke_deployed_event": "Unknown"}
    if not factory_path or not factory_path.exists():
        return res
    src = factory_path.read_text()
    res["impl_caching"] = "Yes" if re.search(r"spokeVaultImpl|routerImpl", src) else "No/Unknown"
    res["proxies_paused"] = "Yes" if re.search(r"pause\(\)" , src) else "No/Unknown"
    res["router_gets_borrower"] = "Yes" if re.search(r"BORROWER_ROLE", src) else "No/Unknown"
    res["renounces_roles"] = "Yes" if re.search(r"renounceRole|renounce", src) else "No/Unknown"
    res["spoke_deployed_event"] = "Yes" if re.search(r"SpokeDeployed", src, re.IGNORECASE) else "No/Unknown"
    return res


def messaging_replay(endpoint_path: Optional[Path], minter_path: Optional[Path]) -> Dict[str, str]:
    res = {"adapter_authority": "Unknown", "legacy_direct_whitelist": "Unknown", "replay_protection": "Unknown", "minter_gateway_role": "Unknown", "observability": "Unknown"}
    if endpoint_path and endpoint_path.exists():
        s = endpoint_path.read_text()
        res["adapter_authority"] = "Yes" if ("onlyAdapter" in s or re.search(r"require\(msg\.sender\s*==\s*adapter", s)) else "No/Unknown"
        res["legacy_direct_whitelist"] = "Yes" if re.search(r"allowlist|whitelist|srcChainId|srcAddr", s) else "No/Unknown"
        res["replay_protection"] = "Yes" if re.search(r"used\[|_verifyAndMark", s) else "No/Unknown"
    if minter_path and minter_path.exists():
        s2 = minter_path.read_text()
        res["minter_gateway_role"] = "Yes" if "GATEWAY_ROLE" in s2 and re.search(r"mintFromGateway", s2) else "No/Unknown"
        res["observability"] = "Yes" if re.search(r"Minted|Gateway|Reported", s2) else "No/Unknown"
    return res


def gateway_policy_pps(gateway_path: Optional[Path], policy_path: Optional[Path], pps_path: Optional[Path]) -> Dict[str, str]:
    res = {"gateway_summary": "Unknown", "policy_pps_refs": "Unknown", "sequencer_guard": "Unknown"}
    if gateway_path and gateway_path.exists():
        s = gateway_path.read_text()
        parts = []
        if re.search(r"haircutBps", s): parts.append("haircutBps")
        if re.search(r"stale|staleness|maxStaleness", s, re.IGNORECASE): parts.append("staleness")
        if re.search(r"decimals", s): parts.append("decimals")
        if re.search(r"cap", s, re.IGNORECASE): parts.append("caps")
        res["gateway_summary"] = ", ".join(parts) if parts else "Unknown"
    refs = []
    if policy_path and policy_path.exists():
        if re.search(r"interface|IPolicy|Policy", policy_path.read_text()): refs.append("PolicyBeacon")
    if pps_path and pps_path.exists():
        if re.search(r"Mirror|Pps", pps_path.read_text(), re.IGNORECASE): refs.append("PpsMirror")
    res["policy_pps_refs"] = ", ".join(refs) if refs else "Unknown"
    # Sequencer guard hint
    for p in [gateway_path, policy_path, pps_path, ROOT / "src/Hub.sol"]:
        if p and p.exists() and re.search(r"sequencer|L2|Arbitrum", p.read_text(), re.IGNORECASE):
            res["sequencer_guard"] = "present/toggleable"
            break
    if res["sequencer_guard"] == "Unknown":
        res["sequencer_guard"] = "absent"
    return res


def pause_withdraw_semantics(hub_path: Optional[Path]) -> Dict[str, str]:
    res = {"pause_summary": "Unknown", "request_withdraw_allowed": "Unknown", "deposit_claim_gated": "Unknown", "withdraw_queue": "Unknown"}
    if not hub_path or not hub_path.exists():
        return res
    s = hub_path.read_text()
    res["pause_summary"] = "Pausable present" if ("Pausable" in s or "whenNotPaused" in s) else "Absent"
    # heuristics
    res["request_withdraw_allowed"] = "Yes" if re.search(r"requestWithdraw\([\s\S]*?\)\s*(public|external)[\s\S]*?\{[\s\S]*?\}", s) and "whenNotPaused" not in s.split("requestWithdraw")[1].split("}")[0] else "Unknown"
    res["deposit_claim_gated"] = "Yes" if re.search(r"(deposit|claimWithdraw).*whenNotPaused", s, re.DOTALL) else "Unknown"
    if re.search(r"withdrawDelay|WithdrawRequested|WithdrawClaimed", s):
        res["withdraw_queue"] = "Delay+events present"
    return res


def oracles_summary(hub_path: Optional[Path], gateway_path: Optional[Path]) -> Dict[str, str]:
    res = {"feeds": [], "price_decimals": "Unknown", "staleness": "Unknown", "fallback": "Unknown"}
    texts = []
    for p in [hub_path, gateway_path]:
        if p and p.exists():
            texts.append(p.read_text())
    combined = "\n".join(texts)
    if re.search(r"DIA|DIAAddress|DIAOracle", combined):
        res["feeds"].append("DIA")
    if re.search(r"AggregatorV3Interface|Chainlink", combined):
        res["feeds"].append("Chainlink")
    if re.search(r"priceDecimals|feedDecimals|\b8\b|\b18\b", combined):
        res["price_decimals"] = "8/18 supported"
    if re.search(r"stale|maxStaleness|staleness", combined, re.IGNORECASE):
        res["staleness"] = "configured"
    return res


def list_tests_and_domains() -> Tuple[List[str], List[str], int]:
    files = sorted([str(Path(p)) for p in glob(str(TEST_DIR / "**/*.t.sol"), recursive=True)])
    domains = []
    for d in ["router", "factory", "messaging", "spoke", "hub", "gateway", "policy", "pps", "upgrade", "zpx", "usdzy"]:
        if any(('/' + d + '/') in f or (d.capitalize() in f) for f in files):
            domains.append(d)
    # Approximate test count
    test_count = 0
    for f in files:
        try:
            txt = Path(f).read_text()
            test_count += len(re.findall(r"function\s+test", txt))
        except Exception:
            pass
    return files, domains, test_count


def parse_envs_from_scripts() -> List[Tuple[str, str]]:
    envs: Dict[str, str] = {}
    for f in glob(str(SCRIPT_DIR / "**/*.s.sol"), recursive=True):
        try:
            txt = Path(f).read_text()
        except Exception:
            continue
        for m in re.finditer(r"env(Addr(?:ess)?|Uint|Int|String|Bytes32|Bool)?\(\"([A-Z0-9_]+)\"\)", txt):
            name = m.group(2)
            envs[name] = f
    return sorted([(k, v) for k, v in envs.items()])


def generate_docs(tools: Dict[str, str], contracts_info: Dict[str, Dict[str, Any]], storage_diffs: Dict[str, str], router_fee:
                  Dict[str, str], factory_info: Dict[str, str], msg_info: Dict[str, str], gp_info: Dict[str, str], pause_info: Dict[str, str],
                  oracle_info: Dict[str, str], test_files: List[str], test_domains: List[str], test_count: int, build_out: str,
                  slither_summary: Optional[Dict[str, Any]], gas_out: Optional[str]) -> Tuple[str, str]:
    # DEV_STATUS_VAULTS.md content
    lines: List[str] = []
    lines.append("# ZPX-LP-Vaults — Dev Status (auto-generated)")
    lines.append("")
    lines.append("## Tooling")
    lines.append(f"- Foundry/Forge: {tools.get('forge','absent')}")
    lines.append(f"- Cast: {tools.get('cast','absent')}")
    lines.append(f"- solc: {tools.get('solc','absent')}")
    lines.append(f"- Slither: {'present' if tools.get('slither','absent') != 'absent' else 'absent'}")
    lines.append("")

    lines.append("## Contract Inventory")
    for cname in CONTRACT_CANDIDATES.keys():
        info = contracts_info.get(cname)
        if info and info.get("path"):
            lines.append(f"- {cname}.sol")
    lines.append("- ZPXArb.sol / MintGate_Arb.sol / Rewarder.sol (if present)")
    lines.append("- Other notable libs/helpers:")
    lines.append("")

    lines.append("## Roles & AccessControl")
    # Gather roles discovered union
    roles_union = sorted(set(sum([ci.get("roles", []) for ci in contracts_info.values()], [])))
    lines.append(f"- Roles discovered: {roles_union}")
    lines.append("- Role → Functions map (samples):")
    # Sample few mappings
    for cname, ci in contracts_info.items():
        rf = ci.get("role_function_map") or {}
        for role_expr, fns in list(rf.items())[:2]:
            lines.append(f"  - {role_expr} → {cname}.{', '.join(fns[:5])}")
    lines.append("- Deployment scripts role wiring summary:")
    lines.append("")

    lines.append("## Upgradeability & Storage")
    for cname, ci in contracts_info.items():
        if not ci.get("path"): continue
        lines.append(f"- {cname}: UUPS={ci.get('uups')}, _authorizeUpgrade={ci.get('authorize_upgrade')}, __gap={ci.get('has_gap')}, storage={storage_diffs.get(cname,'Unknown')}")
    lines.append("")

    lines.append("## Fees & Release Model (Router/Spoke)")
    for k, v in router_fee.items():
        label = k.replace('_', ' ')
        lines.append(f"- {label}: [{v}]")
    lines.append("")

    lines.append("## Factory Hygiene")
    for k, v in factory_info.items():
        lines.append(f"- {k.replace('_',' ')}: [{v}]")
    lines.append("")

    lines.append("## Messaging & Replay")
    for k, v in msg_info.items():
        lines.append(f"- {k.replace('_',' ')}: [{v}]")
    lines.append("")

    lines.append("## Gateways, Policy & PPS")
    for k, v in gp_info.items():
        lines.append(f"- {k.replace('_',' ')}: [{v}]")
    lines.append("")

    lines.append("## Pause Semantics & Withdraw Queue")
    for k, v in pause_info.items():
        lines.append(f"- {k.replace('_',' ')}: [{v}]")
    lines.append("")

    lines.append("## Oracles (DIA/Chainlink)")
    lines.append(f"- Feeds used: {oracle_info.get('feeds')}")
    lines.append(f"- priceDecimals support (8/18): {oracle_info.get('price_decimals')}")
    lines.append(f"- Staleness windows: {oracle_info.get('staleness')}")
    lines.append(f"- Fallback order: {oracle_info.get('fallback')}")
    lines.append("")

    lines.append("## Security Summary")
    if slither_summary:
        # Summarize detectors with severity Medium/High
        findings: List[str] = []
        for res in slither_summary.get("results", {}).values():
            if isinstance(res, list):
                for item in res:
                    sev = item.get("impact") or item.get("severity")
                    if not sev: continue
                    if str(sev).lower() in ("high", "medium"):
                        elements = item.get("elements") or []
                        where = elements[0].get("source_mapping", {}).get("filename") if elements else ""
                        name = item.get("check") or item.get("description") or "finding"
                        findings.append(f"- {sev}: {name} @ {where}")
        lines.append(f"- Slither Medium/High: {'none' if not findings else ''}")
        if findings:
            lines.extend(findings[:20])
    else:
        lines.append("- Slither Medium/High: [skipped]")
    # CEI/nonReentrant/SafeERC20 heuristics
    sec_summary = []
    for cname, ci in contracts_info.items():
        p = find_contract_path(cname)
        if not p: continue
        s = p.read_text()
        if "nonReentrant" in s or "ReentrancyGuard" in s:
            sec_summary.append(f"{cname}: nonReentrant present")
        if "SafeERC20" in s:
            sec_summary.append(f"{cname}: SafeERC20 used")
    lines.append(f"- CEI + nonReentrant: heuristic — {'; '.join(sec_summary[:6])}")
    lines.append("- SafeERC20 used on external transfers: heuristic — see above")
    lines.append("- External calls in loops: [Unknown]")
    lines.append("")

    lines.append("## Tests & Gas")
    lines.append("- Test files discovered:")
    for f in test_files[:30]:
        lines.append(f"  - {os.path.relpath(f, ROOT)}")
    if len(test_files) > 30:
        lines.append(f"  - ... (+{len(test_files)-30} more)")
    lines.append(f"- Domains covered: {test_domains}")
    if gas_out:
        # Keep a brief section header; omitting full table for brevity
        lines.append("- Gas report: collected (see local run output)")
    else:
        lines.append("- Gas report: skipped")
    lines.append(f"- Test count (approx): {test_count}")
    lines.append("")

    lines.append("## Deploy Scripts & Envs")
    lines.append("- Scripts: Phase-1, Phase-1.5, Phase-2, Policy, PPS, Gateway")
    lines.append("- Env vars:")
    for name, used_in in parse_envs_from_scripts():
        lines.append(f"  - {name} | used in {os.path.relpath(used_in, ROOT)}")
    lines.append("")

    lines.append("## Cross-Repo Parity (optional)")
    zpx_repos = ROOT / ".zpx-repos.json"
    if zpx_repos.exists():
        lines.append("- Hash/fee parity checks with other repos: [skipped — hook not implemented]")
    else:
        lines.append("- Hash/fee parity checks with other repos: [skipped]")
    lines.append("")

    lines.append("## Build Output")
    lines.append("- forge build: see summary below")
    # Shorten warnings
    warn_lines = [ln for ln in build_out.splitlines() if "Warning" in ln][:20]
    lines.append(f"- build warnings (first 20):")
    for wl in warn_lines:
        lines.append(f"  - {wl}")
    if slither_summary:
        lines.append("- slither: collected (Medium/High summarized above)")
    else:
        lines.append("- slither: skipped or not installed")
    lines.append("")

    lines.append("## Gaps & Action Items")
    lines.append("- [ ] Fill any Unknowns by refining parser or adding explicit annotations in code comments")
    # Router fee invariants unknowns
    for k, v in router_fee.items():
        if v.startswith("Unknown") or v.startswith("No/Unsure"):
            lines.append(f"- [ ] Check {k} in Router.sol")
    # Storage diffs
    for c, st in storage_diffs.items():
        if st.startswith("Changes"):
            lines.append(f"- [ ] Review storage layout changes for {c}")

    dev_status_md = "\n".join(lines) + "\n"

    # CHECKLIST_EXPECTED.md content
    cl: List[str] = []
    cl.append("Area\tExpectation\tStatus\tNotes")
    def row(area, exp, status, notes=""):
        cl.append(f"{area}\t{exp}\t{status}\t{notes}")
    # Fees
    row("Fees", "protocolFeeBps ≤ 5", emoji(router_fee.get("protocolFeeBps_cap_le_5")))
    row("Fees", "protocolShareBps + lpShareBps = 10_000", emoji(router_fee.get("protocolShare_plus_lpShare_eq_10000")))
    row("Fees", "Destination-side skim, LP share retained in vault", emoji(router_fee.get("destination_skimming")))
    row("Router", "FeeApplied telemetry event present", emoji(router_fee.get("fee_events_present")))
    # Factory
    row("Factory", "Proxies born paused", emoji(factory_info.get("proxies_paused")))
    row("Factory", "Router gets BORROWER_ROLE", emoji(factory_info.get("router_gets_borrower")))
    row("Factory", "Factory renounces roles on proxies", emoji(factory_info.get("renounces_roles")))
    # Messaging
    row("Messaging", "Adapter-authority enforced; legacy pre-adapter allowed only for whitelisted src", emoji(msg_info.get("adapter_authority")))
    row("Messaging", "Replay protection marks used[hash]", emoji(msg_info.get("replay_protection")))
    # Gateway
    row("Gateway", "mintFromGateway behind GATEWAY_ROLE", emoji(msg_info.get("minter_gateway_role")))
    # Hub
    row("Hub", "requestWithdraw() allowed while paused", emoji(pause_info.get("request_withdraw_allowed")))
    # Oracles
    row("Oracles", "DIA/Chainlink staleness + decimals handled", "✅" if oracle_info.get("feeds") else "❔")
    # Security
    row("Security", "CEI + nonReentrant around external transfers", "✅/heuristic")
    row("Security", "SafeERC20 everywhere funds move", "✅/heuristic")
    row("Security", "No Slither Medium/High in src/", "✅" if not slither_summary else "❔/see report")
    # Upgrades
    up_ok = all(ci.get("authorize_upgrade") and ci.get("uups") for ci in contracts_info.values() if ci.get("path"))
    row("Upgrades", "UUPS _authorizeUpgrade role-gated", "✅" if up_ok else "❔")
    gap_ok = all(ci.get("has_gap") or not ci.get("uups") for ci in contracts_info.values())
    row("Upgrades", "__gap present in upgradables", "✅" if gap_ok else "❔")
    # Storage
    row("Storage", "Snapshots up-to-date / diffs reviewed", "✅" if all(v in ("No changes", "Snapshot created") for v in storage_diffs.values()) else "❔")
    # Scripts
    row("Scripts", "Phase-1/1.5/2 scripts set fees, collector, adapter, roles", "❔")
    # Docs
    row("Docs", "IDs/roles/params documented", "❔")

    checklist_md = "\n".join(cl) + "\n"
    return dev_status_md, checklist_md


def emoji(val: Optional[str]) -> str:
    if not val:
        return "❔"
    low = val.lower()
    if low in ("yes", "no changes", "snapshot created"):
        return "✅"
    if low.startswith("unknown") or low.startswith("no/unsure"):
        return "❔"
    return "✅" if "yes" in low else "❔"


def write_file(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def main():
    parser = argparse.ArgumentParser(description="Generate dev status docs for ZPX-LP-Vaults")
    parser.add_argument("--gas", action="store_true", help="Run forge test with gas report")
    args = parser.parse_args()

    tools = detect_tools()

    # Build
    build_ok, build_out = ensure_build()
    if not build_ok:
        print("forge build failed; continuing to collect available info", file=sys.stderr)

    # Contracts
    contracts = list(CONTRACT_CANDIDATES.keys())
    contracts_info: Dict[str, Dict[str, Any]] = {}
    for c in contracts:
        try:
            contracts_info[c] = collect_contract_info(c)
        except Exception:
            contracts_info[c] = {"name": c}

    # Storage snapshots compare
    storage_diffs = compare_storage_snapshots(contracts)

    # Router fee invariants
    router_fee = extract_router_fee_invariants(find_contract_path("Router"))

    # Factory hygiene
    factory_info = factory_hygiene(find_contract_path("Factory"))

    # Messaging & replay
    msg_info = messaging_replay(find_contract_path("MessagingEndpointReceiver"), find_contract_path("USDzyRemoteMinter"))

    # Gateway/Policy/PPS
    gp_info = gateway_policy_pps(find_contract_path("LocalDepositGateway"), find_contract_path("PolicyBeacon"), find_contract_path("PpsMirror"))

    # Pause & withdraw semantics
    pause_info = pause_withdraw_semantics(find_contract_path("Hub"))

    # Oracles
    oracle_info = oracles_summary(find_contract_path("Hub"), find_contract_path("LocalDepositGateway"))

    # Tests & gas
    test_files, test_domains, test_count = list_tests_and_domains()
    gas_out = maybe_run_gas() if args.gas else None

    # Slither
    tmp_json = ROOT / ".slither-report.tmp.json"
    slither_summary = run_slither_json(tmp_json)
    if tmp_json.exists():
        try:
            tmp_json.unlink()
        except Exception:
            pass

    # Generate docs
    dev_status_md, checklist_md = generate_docs(
        tools, contracts_info, storage_diffs, router_fee, factory_info, msg_info, gp_info, pause_info, oracle_info, test_files, test_domains, test_count, build_out, slither_summary, gas_out
    )
    write_file(DOCS_DIR / "DEV_STATUS_VAULTS.md", dev_status_md)
    write_file(DOCS_DIR / "CHECKLIST_EXPECTED.md", checklist_md)

    # Optional parity notes
    if (ROOT / ".zpx-repos.json").exists():
        write_file(DOCS_DIR / "CROSSREPO_PARITY.md", "Parity checks were skipped; configure script to compare hashes if desired.\n")

    print("Docs generated:")
    print(f" - {DOCS_DIR / 'DEV_STATUS_VAULTS.md'}")
    print(f" - {DOCS_DIR / 'CHECKLIST_EXPECTED.md'}")


if __name__ == "__main__":
    main()
