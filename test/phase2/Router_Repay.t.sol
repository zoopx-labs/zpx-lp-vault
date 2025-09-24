// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "src/router/Router.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

// Covers Router.repay path including event emission and vault interaction
contract RouterRepayTest is Test {
    Router router;
    SpokeVault vault;
    MockERC20 token;
    address admin = address(0xA11CE);
    address relayer = address(0xBEEF);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN");
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", admin))
        );
        vault = SpokeVault(vProxy);
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl), abi.encodeCall(Router.initialize, (address(vault), address(0x1), admin, address(0xC0FFEE)))
        );
        router = Router(rProxy);

        // allow router to borrow so we can create debt, then repay
        vm.startPrank(admin);
        vault.grantRole(vault.BORROWER_ROLE(), address(router));
        router.grantRole(router.RELAYER_ROLE(), relayer); // for creating a fill
        router.setFeeCollector(address(0xFEE));
        router.setProtocolFeeBps(0); // keep zero so collector can remain zero if needed
        router.setRelayerFeeBps(0); // simplify math
        vm.stopPrank();

        // fund vault
        token.mint(address(vault), 1_000_000e6);
    }

    function testRepayFlow() public {
        // create debt by calling fill as relayer (net borrow to user)
        uint256 amount = 100_000;
        address user = address(0xCAFE);
        vm.prank(relayer);
        router.fill(user, amount);
        uint256 debtBefore = vault.debt();
        assertGt(debtBefore, 0, "debt created");

        // Router.repay: 1) pulls tokens from user into vault; 2) calls vault.repay which pulls from router (msg.sender) not user.
        // Provide user funds for first pull and router funds+approval for second.
        token.mint(user, amount);
        token.mint(address(router), amount);
        vm.prank(address(router));
        token.approve(address(vault), amount); // for vault.repay transfer
        vm.prank(user);
        token.approve(address(router), amount); // for initial router pull
        uint256 userBefore = token.balanceOf(user);
        uint256 routerBefore = token.balanceOf(address(router));
        vm.prank(user);
        router.repay(amount);
        assertEq(vault.debt(), debtBefore - amount, "debt decreased by amount");
        assertEq(token.balanceOf(user), userBefore - amount, "user paid amount once");
        assertEq(token.balanceOf(address(router)), routerBefore - amount, "router contributed second tranche");
    }
}
