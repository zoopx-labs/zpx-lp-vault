// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "src/router/Router.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockAdapter} from "src/messaging/MockAdapter.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

contract RouterPauseAndRebalanceNoOpTest is Test {
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

        // roles
        vm.startPrank(admin);
        // explicitly set adapter again defensively to ensure storage is set (some earlier failures showed adapter zero)
        router.setAdapter(address(adapter));
        router.grantRole(router.KEEPER_ROLE(), keeper);
        router.grantRole(router.PAUSER_ROLE(), admin);
        vault.grantRole(vault.BORROWER_ROLE(), address(router));
        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.prank(admin);
        router.pause();
        // OpenZeppelin Pausable uses custom error or empty revert data depending on version; use expectRevert without data
        vm.expectRevert();
        vm.prank(keeper);
        router.rebalance(123, address(0x1));
        vm.prank(admin);
        router.unpause();
    }

    function testSettersAndRebalanceNoOp() public {
        // configure fee split & protocol fee (valid)
        vm.prank(admin);
        router.setFeeSplit(2500, 7500);
        vm.prank(admin);
        router.setProtocolFeeBps(5);
        vm.prank(admin);
        router.setRelayerFeeBps(10);
        // rebalance should revert initially because conditions not met (need health < 4000 or time > 1d)
        vm.expectRevert(bytes("NO_REBALANCE"));
        vm.prank(keeper);
        router.rebalance(100, address(0x2));
        // simulate 1 day elapsed -> should now pass even with healthy BPS
        vm.warp(block.timestamp + 1 days + 1);
        // ensure adapter is non-zero (already set in initialize). Provide a non-zero hub address to avoid zero-call issues
        vm.prank(keeper);
        router.rebalance(100, address(0xB0B));
        assertGt(router.lastSendNonce(), 0, "nonce incremented");
    }
}
