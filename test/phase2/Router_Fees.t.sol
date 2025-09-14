// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "../..//src/mocks/MockERC20.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {Router} from "../../src/router/Router.sol";

contract RouterFeesTest is Test {
    MockERC20 token;
    SpokeVault vault;
    Router router;
    address admin = address(0xABCD);
    address relayer = address(0xBEEF);
    address user = address(0xCAFE);
    address treasury = address(0xD00D);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN");
        // deploy vault and router implementations and proxies minimal by direct deployment for test
        vault = new SpokeVault();
        vault.initialize(address(token), "svT", "svT", admin);
        router = new Router();
        router.initialize(address(vault), address(0x1), admin, address(0));

        // fund vault with tokens to allow borrows
        token.mint(address(vault), 1_000_000e6);

        // grant relayer role and BORROWER_ROLE on vault to router so router can borrow to recipients
        vm.startPrank(admin);
        router.grantRole(keccak256("RELAYER_ROLE"), relayer);
        vault.grantRole(vault.BORROWER_ROLE(), address(router));
        vm.stopPrank();
    }

    function testHappyPathFees() public {
        uint256 amount = 1_000_000; // 1e6 units (assume 6 decimals semantics in test)

        // configure fees
        vm.prank(admin);
        router.setFeeCollector(treasury);
        vm.prank(admin);
        router.setProtocolFeeBps(5); // 5 bps
        vm.prank(admin);
        router.setRelayerFeeBps(20); // 20 bps
        vm.prank(admin);
        router.setFeeSplit(2500, 7500); // 25% treasury, 75% LPs

        // balances before
        uint256 balTreasBefore = token.balanceOf(treasury);
        uint256 balVaultBefore = token.balanceOf(address(vault));
        uint256 balRelayerBefore = token.balanceOf(relayer);
        uint256 balUserBefore = token.balanceOf(user);

        // call fill as relayer
        vm.prank(relayer);
        router.fill(user, amount);

        // compute expected
        uint256 protocolFee = (amount * 5) / 10000; // 0.0005 * amount
        uint256 relayerFee = (amount * 20) / 10000; // 0.0020 * amount
        uint256 net = amount - protocolFee - relayerFee;
        uint256 toTreas = (protocolFee * 2500) / 10000;
        uint256 toLPs = protocolFee - toTreas;

        assertEq(token.balanceOf(treasury), balTreasBefore + toTreas);
        // vault should have lost (amount - toLPs) since toLPs remains in vault while amount was partially sent out
        assertEq(token.balanceOf(address(vault)), balVaultBefore + toLPs - amount);
        assertEq(token.balanceOf(relayer), balRelayerBefore + relayerFee);
        assertEq(token.balanceOf(user), balUserBefore + net);
    }

    function testProtocolFeeCapEnforced() public {
        vm.prank(admin);
        vm.expectRevert(bytes("ProtocolFee>5bps"));
        router.setProtocolFeeBps(6);
    }

    function testSplitSumEnforced() public {
        vm.prank(admin);
        vm.expectRevert(bytes("Split!=100%"));
        router.setFeeSplit(2500, 7400);
    }

    function testFeeCollectorRequired() public {
        vm.prank(admin);
        router.setProtocolFeeBps(1);
        // set collector to zero
        vm.prank(admin);
        vm.expectRevert(bytes("FeeCollector=0"));
        router.setFeeCollector(address(0));
    }
}
