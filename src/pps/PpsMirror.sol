// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../pps/IPpsSource.sol";

contract PpsMirror is Initializable, UUPSUpgradeable, AccessControlUpgradeable, IPpsSource {
    bytes32 public constant POSTER_ROLE = keccak256("POSTER_ROLE");

    uint256 public pps6;
    uint64 public asOf;
    uint64 public maxStaleness;

    event PpsMirrored(uint256 pps6, uint64 asOf);

    function initialize(address admin, uint64 maxStaleness_) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POSTER_ROLE, admin);
        maxStaleness = maxStaleness_;
    }

    function post(uint256 newPps6, uint64 nowTs) external onlyRole(POSTER_ROLE) {
        pps6 = newPps6;
        asOf = nowTs;
        emit PpsMirrored(newPps6, nowTs);
    }

    function latestPps6() external view override returns (uint256, uint64) {
        return (pps6, asOf);
    }

    function setMaxStaleness(uint64 s) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxStaleness = s;
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
