// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "src/router/Router.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockAdapter} from "src/messaging/MockAdapter.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

// Covers time-triggered rebalance path (secondary path) ensuring needsRebalance via time elapse
contract RouterRebalanceHealthTest is Test {
    Router router;
    SpokeVault vault;
    MockERC20 token;
    MockAdapter adapter;
    address admin = address(0xA11CE);
    address keeper = address(0xBEEF);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN");
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", admin))
        );
        vault = SpokeVault(vProxy);
        adapter = new MockAdapter();
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl),
            abi.encodeCall(Router.initialize, (address(vault), address(adapter), admin, address(0xC0FFEE)))
        );
        router = Router(rProxy);
        vm.startPrank(admin);
        router.grantRole(router.KEEPER_ROLE(), keeper);
        vault.grantRole(vault.BORROWER_ROLE(), address(router));
        // defensive: ensure adapter set (initialize passed it but mirror earlier fix pattern)
        router.setAdapter(address(adapter));
        vm.stopPrank();
        // seed vault TVL
        token.mint(address(vault), 1_000_000e6);
    }

    function testTimeTriggeredRebalance() public {
        // initial attempt should revert (no time elapsed)
        vm.prank(keeper);
        vm.expectRevert(bytes("NO_REBALANCE"));
        router.rebalance(200, address(0xB0B));
        // warp forward 1 day
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(keeper);
        router.rebalance(200, address(0xB0B));
        assertEq(router.lastSendNonce(), 1);
    }
}
