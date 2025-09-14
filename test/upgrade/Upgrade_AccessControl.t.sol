// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Router} from "../../src/router/Router.sol";
import {Hub} from "../../src/Hub.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
}

contract UpgradeAccessControlTest is Test {
    function _deployProxy(address implAddr, bytes memory init) internal returns (address) {
        ERC1967Proxy p = new ERC1967Proxy(implAddr, init);
        return address(p);
    }

    function testNonAdminCannotUpgradeRouter() public {
        Router impl = new Router();
        address admin = address(this);
        bytes memory init = abi.encodeCall(Router.initialize, (address(0x1), address(0x2), admin, address(0)));
        address proxy = _deployProxy(address(impl), init);
        Router router = Router(proxy);

        Router impl2 = new Router();

    address attacker = address(0xBEEF);
    vm.prank(attacker);
    vm.expectRevert();
    // call upgradeTo via proxy - should revert due to _authorizeUpgrade
    IUUPS(proxy).upgradeTo(address(impl2));
    }

    function testNonAdminCannotUpgradeHub() public {
        Hub impl = new Hub();
        address admin = address(this);
        bytes memory init = abi.encodeCall(Hub.initialize, (address(0x1), admin));
        address proxy = _deployProxy(address(impl), init);
        Hub hub = Hub(proxy);

        Hub impl2 = new Hub();

    address attacker = address(0xBEEF);
    vm.prank(attacker);
    vm.expectRevert();
    IUUPS(proxy).upgradeTo(address(impl2));
    }

    function testNonAdminCannotUpgradeSpokeVault() public {
        SpokeVault impl = new SpokeVault();
        address admin = address(this);
        bytes memory init = abi.encodeCall(SpokeVault.initialize, (address(0x1), string("n"), string("s"), admin));
        address proxy = _deployProxy(address(impl), init);
        SpokeVault v = SpokeVault(proxy);

        SpokeVault impl2 = new SpokeVault();

    address attacker = address(0xBEEF);
    vm.prank(attacker);
    vm.expectRevert();
    IUUPS(proxy).upgradeTo(address(impl2));
    }
}
