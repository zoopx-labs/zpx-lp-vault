// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

contract SpokeVaultERC4626DisabledTest is Test {
    SpokeVault vault;
    MockERC20 assetToken;

    function setUp() public {
        assetToken = new MockERC20("ASSET", "AST");
        SpokeVault impl = new SpokeVault();
        address proxy = ProxyUtils.deployProxy(
            address(impl), abi.encodeCall(SpokeVault.initialize, (address(assetToken), "SV", "SV", address(this)))
        );
        vault = SpokeVault(proxy);
    }

    function test_disabled_erc4626_flows_revert() public {
        vm.expectRevert(SpokeVault.LP_DISABLED.selector);
        vault.deposit(1, address(this));
        vm.expectRevert(SpokeVault.LP_DISABLED.selector);
        vault.mint(1, address(this));
        vm.expectRevert(SpokeVault.LP_DISABLED.selector);
        vault.withdraw(1, address(this), address(this));
        vm.expectRevert(SpokeVault.LP_DISABLED.selector);
        vault.redeem(1, address(this), address(this));
    }
}
