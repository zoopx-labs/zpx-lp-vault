// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SpokeVaultSendIdlePolicyTest is Test {
    SpokeVault sv;
    MockERC20 token;
    address admin = address(this);

    function setUp() public {
        token = new MockERC20("T", "T");
        SpokeVault impl = new SpokeVault();
        address proxy = ProxyUtils.deployProxy(
            address(impl), abi.encodeCall(SpokeVault.initialize, (address(token), "sv", "sv", admin))
        );
        sv = SpokeVault(proxy);
        token.mint(address(sv), 10000);
    }

    function testAdminCanUpdateCapsAndSendIdle() public {
        // default borrow cap is large; set a smaller borrow cap and ensure borrow respects it
        sv.setBorrowCap(5000);
        assertEq(sv.maxBorrow(), 5000);

        // sendIdle should be allowed up to idleLiquidity
        uint256 idle = sv.idleLiquidity();
        assertTrue(idle > 0);
        sv.sendIdle(address(0xBEEF), idle);
        assertEq(token.balanceOf(address(0xBEEF)), idle);
    }

    function testHandoverAdminThenSendIdle() public {
        address newAdmin = address(0xCAFE);
        // grant admin role to newAdmin and renounce ours
        sv.grantRole(sv.DEFAULT_ADMIN_ROLE(), newAdmin);
        sv.grantRole(sv.PAUSER_ROLE(), newAdmin);
        sv.renounceRole(sv.DEFAULT_ADMIN_ROLE(), address(this));
        sv.renounceRole(sv.PAUSER_ROLE(), address(this));

        // now only newAdmin can call sendIdle
        vm.prank(newAdmin);
        sv.sendIdle(address(0xDEAD), 10);
        assertEq(token.balanceOf(address(0xDEAD)), 10);
    }
}
