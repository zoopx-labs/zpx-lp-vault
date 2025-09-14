// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PolicyBeacon} from "../src/policy/PolicyBeacon.sol";
import {IPolicySource} from "../src/policy/IPolicySource.sol";

contract DeployPolicyBeacon is Script {
    // Required envs:
    // - POLICY_BEACON_ADMIN (address)
    // - POLICY_POSTER (address)  // granted POSTER_ROLE

    function run() external {
        address admin = vm.envAddress("POLICY_BEACON_ADMIN");
        address poster = vm.envAddress("POLICY_POSTER");

        vm.startBroadcast();
        PolicyBeacon b = new PolicyBeacon();
        b.initialize(admin);
        bytes32 POSTER = keccak256("POSTER_ROLE");
        b.grantRole(POSTER, poster);
        // emit a sample post
        b.post(
            uint64(block.chainid),
            address(0xBEEF),
            address(0xCAFE),
            1_000_000,
            900_000,
            5000,
            IPolicySource.State.Ok,
            uint64(block.timestamp),
            bytes32("sample"),
            true
        );
        console.log("PolicyBeacon deployed: %s", address(b));
        console.log("POSTER_ROLE granted to: %s", poster);
        vm.stopBroadcast();
    }
}
