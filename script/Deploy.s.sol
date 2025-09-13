// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import "src/mocks/MockERC20.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast();

        MockERC20 stake = new MockERC20("Stake", "STK");
        MockERC20 reward = new MockERC20("Reward", "RWD");

        // simple deploy script for local mock tokens
        console2.log("Stake:", address(stake));
        console2.log("Reward:", address(reward));

        vm.stopBroadcast();
    }
}
