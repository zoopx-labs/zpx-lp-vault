// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function approve(address, uint256) external returns (bool) {
        return true;
    }

    function setBalance(address who, uint256 v) external {
        balanceOf[who] = v;
    }
}

contract SpokeSendIdleCapsTest is Test {
    SpokeVault sv;
    MockToken t;

    function setUp() public {
        t = new MockToken();
        SpokeVault impl = new SpokeVault();
        address proxy = ProxyUtils.deployProxy(
            address(impl), abi.encodeCall(SpokeVault.initialize, (address(t), "Spk", "SPK", address(this)))
        );
        sv = SpokeVault(proxy);
        t.setBalance(address(sv), 1000);
    }

    function testOnlyAdminCanSendIdle() public {
        vm.expectRevert();
        // try from non-admin
        vm.prank(address(0xBEEF));
        sv.sendIdle(address(0xBEEF), 1);

        // admin should succeed
        sv.sendIdle(address(0xBEEF), 100);
        assertEq(t.balanceOf(address(0xBEEF)), 100);
    }

    function testCannotExceedIdle() public {
        vm.expectRevert(bytes("OVER_IDLE"));
        sv.sendIdle(address(0xBEEF), 2000);
    }
}
