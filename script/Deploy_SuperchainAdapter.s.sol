// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {AdapterRegistry} from "src/messaging/AdapterRegistry.sol";
import {SuperchainAdapter} from "src/messaging/SuperchainAdapter.sol";

/// @notice Deployment script for Superchain Adapter + Registry (Variant B)
/// Env Vars (examples):
///   REGISTRY_ADDRESS (optional; if set, reuse existing)
///   MESSENGER_ADDRESS=<address of canonical L2->L2 messenger>
///   ENDPOINT_ADDRESS=<MessagingEndpointReceiver proxy address>
///   REMOTE_CHAINIDS="8453,42161" (comma separated list for initial config)
///   REMOTE_ADAPTER_8453=<addr> REMOTE_ADAPTER_42161=<addr> ... (optional existing remote adapters to pre-configure)
///   PAUSE_ON_DEPLOY=1 (optional)  -> immediately pause adapter
contract Deploy_SuperchainAdapter is Script {
    function run() external {
        vm.startBroadcast();

        address registryAddr = vm.envOr("REGISTRY_ADDRESS", address(0));
        AdapterRegistry registry;
        if (registryAddr == address(0)) {
            registry = new AdapterRegistry();
            console2.log("Deployed AdapterRegistry", address(registry));
        } else {
            registry = AdapterRegistry(registryAddr);
            console2.log("Reusing AdapterRegistry", address(registry));
        }

        address messenger = vm.envAddress("MESSENGER_ADDRESS");
        address endpoint = vm.envAddress("ENDPOINT_ADDRESS");

        SuperchainAdapter adapter = new SuperchainAdapter(messenger, address(registry), endpoint);
        console2.log("Deployed SuperchainAdapter", address(adapter));

        // Optional initial remote configuration
        if (vm.envExists("REMOTE_CHAINIDS")) {
            string memory csv = vm.envString("REMOTE_CHAINIDS");
            // parse simple comma-separated list
            bytes memory b = bytes(csv);
            uint256 start = 0; uint256 i = 0;
            while (i <= b.length) {
                if (i == b.length || b[i] == ",") {
                    if (i > start) {
                        uint256 chainId = _parseUint(_slice(b, start, i));
                        string memory key = string(abi.encodePacked("REMOTE_ADAPTER_", _uintToString(chainId)));
                        if (vm.envExists(key)) {
                            address ra = vm.envAddress(key);
                            registry.setRemoteAdapter(chainId, ra);
                            console2.log("Configured remote adapter", chainId, ra);
                        }
                    }
                    start = i + 1;
                }
                unchecked { ++i; }
            }
        }

        if (vm.envOr("PAUSE_ON_DEPLOY", uint256(0)) == 1) {
            adapter.setPaused(true);
            console2.log("Adapter paused on deploy");
        }

        vm.stopBroadcast();
    }

    function _slice(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory) {
        bytes memory out = new bytes(end - start);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[start + i];
        }
        return out;
    }

    function _parseUint(bytes memory s) internal pure returns (uint256 r) {
        for (uint256 i; i < s.length; ++i) {
            uint8 c = uint8(s[i]);
            if (c >= 48 && c <= 57) {
                r = r * 10 + (c - 48);
            }
        }
    }

    function _uintToString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 len; uint256 vv = v;
        while (vv > 0) { len++; vv /= 10; }
        bytes memory out = new bytes(len);
        while (v > 0) { out[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(out);
    }
}
