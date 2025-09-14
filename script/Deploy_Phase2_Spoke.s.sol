// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Factory} from "../src/factory/Factory.sol";
import {SpokeVault} from "../src/spoke/SpokeVault.sol";
import {Router} from "../src/router/Router.sol";

contract DeployPhase2Spoke is Script {
    function run() external {
        // env vars
        address factory = vm.envAddress("FACTORY_ADDR");
        address asset = vm.envAddress("SPOKE_ASSET");
        address admin = vm.envAddress("SPOKE_ADMIN");
        address routerAdmin = vm.envAddress("ROUTER_ADMIN");
        address adapter = vm.envAddress("ADAPTER_ADDR");
        // feeCollector optional: use envAddress but allow zero address if not set
        address feeCollector = vm.envAddress("FEE_COLLECTOR");
        uint64 chainId = uint64(block.chainid);

        vm.startBroadcast();
        (address v, address r) =
            Factory(factory).deploySpoke(chainId, asset, "svT", "svT", admin, routerAdmin, adapter, feeCollector);
        console.log("Spoke deployed: vault=%s router=%s", v, r);
        vm.stopBroadcast();

        // optional post-deploy: grant KEEPER to env KEEPER_ADDR
        address keeper = vm.envAddress("KEEPER_ADDR");
        if (keeper != address(0)) {
            vm.startBroadcast();
            Router(r).grantRole(keccak256("KEEPER_ROLE"), keeper);
            vm.stopBroadcast();
            console.log("Granted KEEPER to %s", keeper);
        }

        // Optional: configure router fees via env vars
        address feeCollectorEnv = vm.envAddress("FEE_COLLECTOR");
        uint256 protocolFee = vm.envOr("PROTOCOL_FEE_BPS", uint256(0));
        uint256 relayerFee = vm.envOr("RELAYER_FEE_BPS", uint256(0));
        uint256 protocolShare = vm.envOr("PROTOCOL_SHARE_BPS", uint256(2500));
        if (feeCollectorEnv != address(0)) {
            vm.startBroadcast();
            Router(r).setFeeCollector(feeCollectorEnv);
            if (protocolFee > 0) Router(r).setProtocolFeeBps(uint16(protocolFee));
            if (relayerFee > 0) Router(r).setRelayerFeeBps(uint16(relayerFee));
            if (protocolShare != 0) Router(r).setFeeSplit(uint16(protocolShare), uint16(10000 - protocolShare));
            vm.stopBroadcast();
            console.log(
                "Configured router fees: protocol=%s relayer=%s protocolShare=%s",
                protocolFee,
                relayerFee,
                protocolShare
            );
        }
    }
}
