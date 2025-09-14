// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PpsMirror} from "../src/pps/PpsMirror.sol";

contract DeployPpsMirror is Script {
    // Required envs:
    // - PPS_MIRROR_ADMIN (address)
    // - PPS_POSTER (address)  // granted POSTER_ROLE after deploy

    function run() external {
        address admin = vm.envAddress("PPS_MIRROR_ADMIN");
        address poster = vm.envAddress("PPS_POSTER");

        vm.startBroadcast();
        PpsMirror m = new PpsMirror();
        m.initialize(admin, 3600);
        // grant poster
        bytes32 POSTER = keccak256("POSTER_ROLE");
        m.grantRole(POSTER, poster);
        console.log("PpsMirror deployed: %s", address(m));
        console.log("POSTER_ROLE granted to: %s", poster);
        vm.stopBroadcast();
    }
}
