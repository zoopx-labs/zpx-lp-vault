// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract SharesAggregator is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    uint256 public totalGlobalShares;
    mapping(uint64 => uint256) public perChainShares;
    address public adapter;

    event ReportMint(uint64 chainId, uint256 shares);
    event ReportBurn(uint64 chainId, uint256 shares);

    function initialize(address admin) public initializer {
    require(admin != address(0), "admin zero");
    __AccessControl_init();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function setAdapter(address a) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(a != address(0), "adapter zero");
    adapter = a;
    }

    function reportMint(uint64 srcChainId, uint256 shares) external {
        require(msg.sender == adapter, "NOT_ADAPTER");
        perChainShares[srcChainId] += shares;
        totalGlobalShares += shares;
        emit ReportMint(srcChainId, shares);
    }

    function reportBurn(uint64 srcChainId, uint256 shares) external {
        require(msg.sender == adapter, "NOT_ADAPTER");
        uint256 prev = perChainShares[srcChainId];
        if (shares >= prev) perChainShares[srcChainId] = 0;
        else perChainShares[srcChainId] = prev - shares;
        if (shares >= totalGlobalShares) totalGlobalShares = 0;
        else totalGlobalShares -= shares;
        emit ReportBurn(srcChainId, shares);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
