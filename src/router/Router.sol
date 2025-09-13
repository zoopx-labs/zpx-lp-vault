// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    ISpokeVault public vault;
    IMessagingAdapter public adapter;
    address public feeCollector;

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
        vault = ISpokeVault(vault_);
        adapter = IMessagingAdapter(adapter_);
        feeCollector = feeCollector_;
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        // give the admin pauser capability by default for safer ops
        _grantRole(PAUSER_ROLE, admin_);
    }

    function tvl() public view returns (uint256) {
        return vault.totalAssets();
    }

    function pokeTvlSnapshot() public {
        uint64 day = uint64(block.timestamp / 1 days);
        if (day == lastSnapDay) return; // idempotent
        lastSnapDay = day;
        idx = uint8((uint256(idx) + 1) % 7);
        daysBuf[idx] = Day({day: day, tvl: tvl()});
    }

    function avg7d() public view returns (uint256) {
        uint256 s;
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
        if (block.timestamp - lastRebalanceAt >= 1 days) return true;
        return false;
    }

    function rebalance(uint64 dstChainId, address hubAddr) external onlyRole(KEEPER_ROLE) whenNotPaused {
        require(needsRebalance(), "NO_REBALANCE");
        uint256 cur = tvl();
        uint256 avg = avg7d();
        uint16 h = healthBps();
        emit RebalanceSuggested(cur, avg, h, lastRebalanceAt);
        bytes memory payload = abi.encode(dstChainId, address(vault), vault.totalAssets(), cur, h);
        adapter.send(dstChainId, hubAddr, payload);
        lastRebalanceAt = uint64(block.timestamp);
    }

    function fill(address to, uint256 amount) external onlyRole(RELAYER_ROLE) nonReentrant whenNotPaused {
        vault.borrow(amount, to);
        emit FillExecuted(to, amount);
    }

    function repay(uint256 amount) external nonReentrant whenNotPaused {
        IERC20(vault.asset()).transferFrom(msg.sender, address(vault), amount);
        vault.repay(amount);
        emit Repaid(amount, 0);
    }

    function setAdapter(address a) external onlyRole(DEFAULT_ADMIN_ROLE) {
        adapter = IMessagingAdapter(a);
    }

    function setFeeCollector(address f) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeCollector = f;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
