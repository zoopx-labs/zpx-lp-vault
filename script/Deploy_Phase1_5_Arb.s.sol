// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ZPXArb} from "../src/zpx/ZPXArb.sol";
import {MintGate_Arb} from "../src/zpx/MintGate_Arb.sol";
import {ZPXRewarder} from "../src/zpx/ZPXRewarder.sol";

contract DeployPhase15Arb is Script {
    function run() external {
        address zpxAdmin = vm.envAddress("ZPX_ADMIN");
        address usdzyAddr = vm.envAddress("USDZY_ADDR");
        address usdzyAdmin = vm.envOr("USDZY_ADMIN", zpxAdmin);
        uint64 srcChain = uint64(vm.envUint("MINT_ENDPOINT_SRC_CHAINID"));
        address srcAddr = vm.envAddress("MINT_ENDPOINT_SRC_ADDR");
        address keeper = vm.envOr("KEEPER", address(0));

        require(zpxAdmin != address(0), "ZPX_ADMIN required");
        require(usdzyAddr != address(0), "USDZY_ADDR required");
        require(srcAddr != address(0), "MINT_ENDPOINT_SRC_ADDR required");

        vm.startBroadcast();

        ZPXArb z = new ZPXArb();
        z.initialize("ZPX", "ZPX", zpxAdmin);

        MintGate_Arb gate = new MintGate_Arb(address(z));
        gate.setEndpoint(srcChain, srcAddr);
        // grant gate minter role
        z.grantRole(z.MINTER_ROLE(), address(gate));
        // transfer admin to timelock and revoke deployer
        z.grantRole(z.DEFAULT_ADMIN_ROLE(), zpxAdmin);
        z.revokeRole(z.DEFAULT_ADMIN_ROLE(), msg.sender);

        // deploy rewarder with admin timelock
        ZPXRewarder r = new ZPXRewarder(usdzyAddr, address(z), zpxAdmin);
        r.grantRole(r.TOPUP_ROLE(), address(gate));
        r.revokeRole(r.DEFAULT_ADMIN_ROLE(), msg.sender);

        // optional top-up
        uint256 top = vm.envOr("ZPX_TOPUP_AMOUNT", uint256(0));
        uint64 dur = uint64(vm.envOr("ZPX_TOPUP_DURATION", uint256(0)));
        if (top > 0 && dur > 0) {
            // mint to rewarder via gate
            gate.consumeAndMint(srcChain, srcAddr, 1, address(r), top, bytes32("REWARD_TOPUP"));
            r.notifyTopUp(top, dur);
        }

        // grant keeper if present
        if (keeper != address(0)) {
            // rewarder has no keeper role; hub keeper logic handled elsewhere
        }

        vm.stopBroadcast();
    }
}
