// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {USDzy} from "src/USDzy.sol";
import {Hub} from "src/Hub.sol";

contract DeployPhase1 is Script {
    function run() external {
        vm.startBroadcast();

    // read required addresses from environment
    address usdcToken = vm.envAddress("USDC_TOKEN");
    address usdtToken = vm.envAddress("USDT_TOKEN");
    address daiToken = vm.envAddress("DAI_TOKEN");
    address diaUsdcFeed = vm.envAddress("DIA_USDC_FEED");
    address diaUsdtFeed = vm.envAddress("DIA_USDT_FEED");
    address diaDaiFeed = vm.envAddress("DIA_DAI_FEED");
    address timelockAdmin = vm.envAddress("TIMELOCK_ADMIN");

    require(usdcToken != address(0), "USDC_TOKEN required");
    require(usdtToken != address(0), "USDT_TOKEN required");
    require(daiToken != address(0), "DAI_TOKEN required");
    require(diaUsdcFeed != address(0), "DIA_USDC_FEED required");
    require(diaUsdtFeed != address(0), "DIA_USDT_FEED required");
    require(diaDaiFeed != address(0), "DIA_DAI_FEED required");

    address admin = timelockAdmin == address(0) ? msg.sender : timelockAdmin;

        // read price decimals per feed and validate
    uint8 usdcPriceDecs = uint8(vm.envUint("DIA_USDC_FEED_DECIMALS"));
    uint8 usdtPriceDecs = uint8(vm.envUint("DIA_USDT_FEED_DECIMALS"));
    uint8 daiPriceDecs = uint8(vm.envUint("DIA_DAI_FEED_DECIMALS"));
    require(usdcPriceDecs == 8 || usdcPriceDecs == 18, "USDC_BAD_PRICE_DECS");
    require(usdtPriceDecs == 8 || usdtPriceDecs == 18, "USDT_BAD_PRICE_DECS");
    require(daiPriceDecs == 8 || daiPriceDecs == 18, "DAI_BAD_PRICE_DECS");

    USDzy usdzy = new USDzy();
    usdzy.initialize("USDzy", "USZY", admin);

    Hub hub = new Hub();
    hub.initialize(address(usdzy), admin);

        // grant Hub minter/burner and transfer admin to timelock (or admin fallback)
        usdzy.grantRole(usdzy.MINTER_ROLE(), address(hub));
        usdzy.grantRole(usdzy.BURNER_ROLE(), address(hub));
        usdzy.grantRole(usdzy.DEFAULT_ADMIN_ROLE(), admin);
        usdzy.revokeRole(usdzy.DEFAULT_ADMIN_ROLE(), msg.sender);

        // configure defaults
    hub.setWithdrawDelay(2 hours);
    hub.setMaxStaleness(300);

        // set asset configs: token decimals are 6 for stablecoins
    hub.setAssetConfig(usdcToken, diaUsdcFeed, 6, usdcPriceDecs, 10, true);
    hub.setAssetConfig(usdtToken, diaUsdtFeed, 6, usdtPriceDecs, 15, true);
    hub.setAssetConfig(daiToken, diaDaiFeed, 6, daiPriceDecs, 10, true);

        // grant hub admin/pauser/keeper to timelock
    hub.grantRole(hub.DEFAULT_ADMIN_ROLE(), admin);
    hub.grantRole(hub.PAUSER_ROLE(), admin);
    address keeper = vm.envOr("KEEPER", address(0));
    if (keeper != address(0)) hub.grantRole(hub.KEEPER_ROLE(), keeper);
    hub.revokeRole(hub.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();
    }
}
