// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LocalDepositGateway} from "../src/gateway/LocalDepositGateway.sol";
import {USDzyRemoteMinter} from "../src/usdzy/USDzyRemoteMinter.sol";

contract DeployLocalDepositGateway is Script {
    // Required envs:
    // - GATEWAY_ADMIN (address)         // TIMELOCK_ADMIN or deployer
    // - USDZY_MINTER (address)
    // - PPS_MIRROR (address)
    // - SPOKE_VAULT (address)
    // - ASSET_TOKEN (address)
    // - ASSET_FEED (address)
    // - ASSET_TOKEN_DECIMALS (uint256)
    // - ASSET_PRICE_DECIMALS (uint256)
    // - ASSET_HAIRCUT_BPS (uint256)
    // - MAX_STALENESS (uint256 seconds)
    // Optional per-tx/day caps (env names if present):
    // - PER_TX_CAP_USD6
    // - DAILY_CAP_USD6

    function run() external {
        address admin = vm.envAddress("GATEWAY_ADMIN");
        address usdzyMinter = vm.envAddress("USDZY_MINTER");
        address ppsMirror = vm.envAddress("PPS_MIRROR");
        address spoke = vm.envAddress("SPOKE_VAULT");

        address token = vm.envAddress("ASSET_TOKEN");
        address feed = vm.envAddress("ASSET_FEED");
        uint8 tokenDecimals = uint8(vm.envUint("ASSET_TOKEN_DECIMALS"));
        uint8 priceDecimals = uint8(vm.envUint("ASSET_PRICE_DECIMALS"));
        uint16 haircut = uint16(vm.envUint("ASSET_HAIRCUT_BPS"));
        uint64 maxStaleness = uint64(vm.envUint("MAX_STALENESS"));

        vm.startBroadcast();
        LocalDepositGateway g = new LocalDepositGateway();
        g.initialize(usdzyMinter, ppsMirror, spoke, admin, maxStaleness);
        g.setAssetConfig(token, feed, tokenDecimals, priceDecimals, haircut, true);

        // grant GATEWAY_ROLE on USDzyRemoteMinter to gateway
        bytes32 GATEWAY_ROLE = keccak256("GATEWAY_ROLE");
        USDzyRemoteMinter(usdzyMinter).grantRole(GATEWAY_ROLE, address(g));

        console.log("LocalDepositGateway deployed: %s", address(g));
        console.log("GATEWAY_ROLE granted on USDzyRemoteMinter to: %s", address(g));

        // print role holders
        bytes32 ADMIN = 0x00;
        address timelock = admin;
        console.log("Admin/Timelock: %s", timelock);

        vm.stopBroadcast();
    }
}
