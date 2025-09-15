// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../pps/IPpsSource.sol";

contract PpsBeacon is Initializable, UUPSUpgradeable, AccessControlUpgradeable, IPpsSource {
    bytes32 public constant POSTER_ROLE = keccak256("POSTER_ROLE");

    uint256 public pps6;
    uint64 public asOf;

    event PpsUpdated(uint256 pps6, uint64 asOf);

    function initialize(address admin) public initializer {
        require(admin != address(0), "admin zero");
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POSTER_ROLE, admin);
    }

    function post(uint256 newPps6, uint64 nowTs) external onlyRole(POSTER_ROLE) {
        pps6 = newPps6;
        asOf = nowTs;
        emit PpsUpdated(newPps6, nowTs);
    }

    function latestPps6() external view override returns (uint256, uint64) {
        return (pps6, asOf);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // storage gap for future upgrades
    uint256[50] private __gap;
}
