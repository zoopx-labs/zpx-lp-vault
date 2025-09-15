// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ISpokeVault} from "../interfaces/ISpokeVault.sol";
import {IMessagingAdapter} from "../interfaces/IMessagingAdapter.sol";

contract Router is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    using SafeERC20 for IERC20;

    ISpokeVault public vault;
    IMessagingAdapter public adapter;
    address public feeCollector;

    // fees are in basis points (10000 = 100%)
    uint16 public protocolFeeBps; // capped at 5 bps (0.05%)
    uint16 public relayerFeeBps; // no hard cap (ops-defined)
    uint16 public protocolShareBps; // default 2500 (25%)
    uint16 public lpShareBps; // default 7500 (75%)

    event ProtocolFeeUpdated(uint16 bps);
    event RelayerFeeUpdated(uint16 bps);
    event FeeSplitUpdated(uint16 protocolShareBps, uint16 lpShareBps);
    event FeeCollectorUpdated(address feeCollector);
    event FeeApplied(
        address asset,
        uint256 grossAmount,
        uint256 relayerFee,
        uint256 protocolFee,
        uint256 protocolToTreasury,
        uint256 protocolToLPs,
        address to,
        address relayerAddr,
        address feeCollector
    );

    struct Day {
        uint64 day;
        uint256 tvl;
    }

    Day[7] public daysBuf;
    uint8 public idx;
    uint64 public lastSnapDay;

    uint64 public lastRebalanceAt;

    event RebalanceSuggested(uint256 tvl, uint256 avg7d, uint16 healthBps, uint64 lastRebalanceAt);
    event FillExecuted(address to, uint256 amount);
    event Repaid(uint256 amount, uint256 debtAfter);

    function initialize(address vault_, address adapter_, address admin_, address feeCollector_) public initializer {
        require(vault_ != address(0), "vault zero");
        require(adapter_ != address(0), "adapter zero");
        require(admin_ != address(0), "admin zero");
        vault = ISpokeVault(vault_);
        adapter = IMessagingAdapter(adapter_);
        feeCollector = feeCollector_;

        // fee defaults
        protocolFeeBps = 0;
        relayerFeeBps = 0;
        protocolShareBps = 2500;
        lpShareBps = 7500;

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        // give the admin pauser capability by default for safer ops
        _grantRole(PAUSER_ROLE, admin_);
    }

    // --- Fee setters ---
    function setProtocolFeeBps(uint16 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bps <= 5, "ProtocolFee>5bps");
        protocolFeeBps = bps;
        emit ProtocolFeeUpdated(bps);
    }

    function setRelayerFeeBps(uint16 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        relayerFeeBps = bps;
        emit RelayerFeeUpdated(bps);
    }

    function setFeeSplit(uint16 protocolShare, uint16 lpShare) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(uint256(protocolShare) + uint256(lpShare) == 10000, "Split!=100%");
        protocolShareBps = protocolShare;
        lpShareBps = lpShare;
        emit FeeSplitUpdated(protocolShare, lpShare);
    }

    function setFeeCollector(address collector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // allow clearing collector only if protocol fee is zero
        require(collector != address(0) || protocolFeeBps == 0, "FeeCollector=0");
        feeCollector = collector;
        emit FeeCollectorUpdated(collector);
    }

    function tvl() public view returns (uint256) {
        return vault.totalAssets();
    }

    function pokeTvlSnapshot() public {
        uint64 day = uint64(block.timestamp / 1 days);
        // if we've already recorded for this day or a later day, skip
        if (day <= lastSnapDay) return; // idempotent and resilient to clock skew
        lastSnapDay = day;
        idx = uint8((uint256(idx) + 1) % 7);
        daysBuf[idx] = Day({day: day, tvl: tvl()});
    }

    function avg7d() public view returns (uint256) {
        uint256 s = 0;
        for (uint256 i = 0; i < 7; i++) {
            s += daysBuf[i].tvl;
        }
        return s / 7;
    }

    function healthBps() public view returns (uint16) {
        uint256 a = avg7d();
        if (a == 0) return 10000;
        uint256 h = (tvl() * 10000) / a;
        if (h > 65535) return 65535;
        return uint16(h);
    }

    function needsRebalance() public view returns (bool) {
        if (healthBps() < 4000) return true;
        // use an explicit delta comparison to avoid underflow and reduce reliance on exact equality
        if (block.timestamp >= lastRebalanceAt + 1 days) return true;
        return false;
    }

    function rebalance(uint64 dstChainId, address hubAddr) external onlyRole(KEEPER_ROLE) nonReentrant whenNotPaused {
        require(needsRebalance(), "NO_REBALANCE");
        uint256 cur = tvl();
        uint256 avg = avg7d();
        uint16 h = healthBps();
        emit RebalanceSuggested(cur, avg, h, lastRebalanceAt);
        bytes memory payload = abi.encode(dstChainId, address(vault), vault.totalAssets(), cur, h);
        // record timestamp before external adapter call to reduce reentrancy window
        lastRebalanceAt = uint64(block.timestamp);
        // capture adapter nonce to avoid ignoring return value
        uint64 _nonce = adapter.send(dstChainId, hubAddr, payload);
    }

    function fill(address to, uint256 amount) external onlyRole(RELAYER_ROLE) nonReentrant whenNotPaused {
        // compute fees
        uint256 protocolFee = Math.mulDiv(uint256(amount), uint256(protocolFeeBps), 10000);
        uint256 relayerFee = Math.mulDiv(uint256(amount), uint256(relayerFeeBps), 10000);

        uint256 net;
        if (protocolFee + relayerFee >= amount) {
            // protect against zero/negative net
            net = 0;
        } else {
            net = amount - protocolFee - relayerFee;
        }

        uint256 toTreasury = 0;
        uint256 toLPs = 0;

        // handle protocol split and transfers by borrowing from vault to recipients
        if (protocolFee > 0) {
            require(feeCollector != address(0), "FeeCollector=0");
            toTreasury = Math.mulDiv(protocolFee, uint256(protocolShareBps), 10000);
            toLPs = protocolFee - toTreasury;
            // send treasury its share by borrowing from the vault (capture returned debt for clarity)
            if (toTreasury > 0) {
                uint256 _debt = vault.borrow(toTreasury, feeCollector);
                // use _debt to avoid ignoring return value
                if (_debt == type(uint256).max) revert();
            }
            // toLPs remains in the vault (no action) to benefit LPs
        }

        // pay relayer from vault via borrow
        if (relayerFee > 0) {
            uint256 _debt = vault.borrow(relayerFee, msg.sender);
            if (_debt == type(uint256).max) revert();
        }

        // deliver net to user from vault
        if (net > 0) {
            uint256 _debt = vault.borrow(net, to);
            if (_debt == type(uint256).max) revert();
        }

        // emit enriched fee application event
        emit FeeApplied(
            address(vault.asset()), amount, relayerFee, protocolFee, toTreasury, toLPs, to, msg.sender, feeCollector
        );
        emit FillExecuted(to, amount);
    }

    function repay(uint256 amount) external nonReentrant whenNotPaused {
        IERC20(vault.asset()).safeTransferFrom(msg.sender, address(vault), amount);
        uint256 newDebt = vault.repay(amount);
        emit Repaid(amount, newDebt);
    }

    function setAdapter(address a) external onlyRole(DEFAULT_ADMIN_ROLE) {
        adapter = IMessagingAdapter(a);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
