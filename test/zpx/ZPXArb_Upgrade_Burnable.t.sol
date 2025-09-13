// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ZPXArb} from "../../src/zpx/ZPXArb.sol";
import {ZPXArbV2_Burnable} from "../../src/zpx/ZPXArbV2_Burnable.sol";

contract ZPXArbUpgradeTest is Test {
    address deployer = address(0xBEEF);
    address admin = address(0xCAFE);
    address user = address(0xD00D);

    function setUp() public {
        vm.deal(deployer, 1 ether);
        vm.deal(admin, 1 ether);
        vm.deal(user, 1 ether);
    }

    function test_upgrade_to_v2_and_burn() public {
        vm.prank(deployer);
        ZPXArb impl = new ZPXArb();
        bytes memory data = abi.encodeWithSelector(ZPXArb.initialize.selector, "ZPX", "ZPX", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);

        ZPXArb proxyAsZPX = ZPXArb(address(proxy));

        // grant MINTER_ROLE to deployer for minting test tokens
        vm.startPrank(admin);
        bytes32 minterRole = proxyAsZPX.MINTER_ROLE();
        proxyAsZPX.grantRole(minterRole, deployer);
        vm.stopPrank();

        vm.prank(deployer);
        proxyAsZPX.mint(user, 1000 ether);

        // deploy V2 implementation
        vm.prank(deployer);
        ZPXArbV2_Burnable v2 = new ZPXArbV2_Burnable();

        // admin upgrades to v2
        // prepare init call for v2
        bytes memory initV2 = abi.encodeWithSelector(ZPXArbV2_Burnable.initializeV2_Burnable.selector);
        // upgrade implementation as admin
        vm.prank(admin);
        (bool ok,) =
            address(proxy).call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(v2), initV2));
        require(ok, "upgrade failed");

        // now burn should be available
        ZPXArbV2_Burnable proxyAsV2 = ZPXArbV2_Burnable(address(proxy));
        vm.prank(user);
        proxyAsV2.burn(100 ether);
        assertEq(proxyAsV2.balanceOf(user), 900 ether);

        // grant allowance and burnFrom
        vm.prank(user);
        proxyAsV2.approve(admin, 100 ether);
        vm.prank(admin);
        proxyAsV2.burnFrom(user, 100 ether);
        assertEq(proxyAsV2.balanceOf(user), 800 ether);
    }
}
