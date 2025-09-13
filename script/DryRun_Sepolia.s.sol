// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {USDzy} from "src/USDzy.sol";
import {Hub} from "src/Hub.sol";

contract DryRunSepolia is Script {
    function run() external {
        vm.startBroadcast();

        // required envs
        address usdcToken = vm.envAddress("USDC_TOKEN");
        address usdtToken = vm.envAddress("USDT_TOKEN");
        address daiToken = vm.envAddress("DAI_TOKEN");
        address diaUsdcFeed = vm.envAddress("DIA_USDC_FEED");
        address diaUsdtFeed = vm.envAddress("DIA_USDT_FEED");
        address diaDaiFeed = vm.envAddress("DIA_DAI_FEED");

        require(usdcToken != address(0), "USDC_TOKEN required");
        require(usdtToken != address(0), "USDT_TOKEN required");
        require(daiToken != address(0), "DAI_TOKEN required");
        require(diaUsdcFeed != address(0), "DIA_USDC_FEED required");
        require(diaUsdtFeed != address(0), "DIA_USDT_FEED required");
        require(diaDaiFeed != address(0), "DIA_DAI_FEED required");

        // read feed decimals
        uint8 usdcPriceDecs = uint8(vm.envUint("DIA_USDC_FEED_DECIMALS"));
        uint8 usdtPriceDecs = uint8(vm.envUint("DIA_USDT_FEED_DECIMALS"));
        uint8 daiPriceDecs = uint8(vm.envUint("DIA_DAI_FEED_DECIMALS"));
        require(usdcPriceDecs == 8 || usdcPriceDecs == 18, "USDC_BAD_PRICE_DECS");
        require(usdtPriceDecs == 8 || usdtPriceDecs == 18, "USDT_BAD_PRICE_DECS");
        require(daiPriceDecs == 8 || daiPriceDecs == 18, "DAI_BAD_PRICE_DECS");

        // deploy Phase1
        USDzy usdzy = new USDzy();
        usdzy.initialize("USDzy", "USZY", msg.sender);
        Hub hub = new Hub();
        hub.initialize(address(usdzy), msg.sender);

        usdzy.grantRole(usdzy.MINTER_ROLE(), address(hub));
        usdzy.grantRole(usdzy.BURNER_ROLE(), address(hub));

        hub.setWithdrawDelay(2 hours);
        hub.setMaxStaleness(300);

        hub.setAssetConfig(usdcToken, diaUsdcFeed, 6, usdcPriceDecs, 10, true);

        // perform small deposit and request withdraw to create a ticket
        // NOTE: caller must hold USDC and have approved the Hub to spend 1e6 units (1 USDC)
        hub.deposit(usdcToken, 1_000_000);
        uint256 shares = usdzy.balanceOf(msg.sender);
        hub.requestWithdraw(shares);

        // for a freshly-deployed hub the request id will be 0
        uint256 id = 0;
        (,, uint64 readyAt,) = hub.requests(id);
        console2.log("ticketId:", id);
        console2.log("readyAt:", readyAt);

        vm.stopBroadcast();
    }
}
