// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MockAdapter} from "../src/messaging/MockAdapter.sol";

contract DeployMockAdapter is Script {
    function run() external returns (address) {
        vm.startBroadcast();
        MockAdapter m = new MockAdapter();
        vm.stopBroadcast();
        console.log("MockAdapter deployed:", address(m));
        return address(m);
    }
}
