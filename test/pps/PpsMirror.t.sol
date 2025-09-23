// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PpsMirror} from "src/pps/PpsMirror.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PpsMirrorTest is Test {
    PpsMirror mirror;

    function setUp() public {
        PpsMirror impl = new PpsMirror();
        bytes memory initData = abi.encodeCall(PpsMirror.initialize, (address(this), uint64(1234)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        mirror = PpsMirror(address(proxy));
    }

    function test_post_and_latest() public {
        mirror.post(1_234_567, uint64(block.timestamp));
        (uint256 p, uint64 ts) = mirror.latestPps6();
        assertEq(p, 1_234_567);
        assertEq(ts, uint64(block.timestamp));
    }

    function test_post_revert_without_role() public {
        address attacker = address(0xBEEF);
        vm.prank(attacker);
        vm.expectRevert(); // AccessControl revert
        mirror.post(1, 1);
    }

    function test_setMaxStaleness() public {
        mirror.setMaxStaleness(999);
        assertEq(mirror.maxStaleness(), 999);
    }
}
