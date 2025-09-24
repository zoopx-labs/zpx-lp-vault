// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {AdapterRegistry} from "src/messaging/AdapterRegistry.sol";

contract AdapterRegistryTest is Test {
    AdapterRegistry reg;
    address owner;
    address other = address(0xBEEF);

    function setUp() public {
        owner = address(this);
        reg = new AdapterRegistry(); // owner = this
    }

    function test_set_and_get_remoteAdapter() public {
        uint256 chainId = 8453; // base
        address adapter = address(0xA11CE);
        reg.setRemoteAdapter(chainId, adapter);
        assertEq(reg.remoteAdapterOf(chainId), adapter, "adapter stored");
    }

    function test_onlyOwner_can_set() public {
        uint256 chainId = 10; // OP
        vm.prank(other);
        vm.expectRevert(bytes("NOT_OWNER"));
        reg.setRemoteAdapter(chainId, address(0x1234));
    }

    function test_overwrite_remoteAdapter() public {
        uint256 chainId = 77777;
        reg.setRemoteAdapter(chainId, address(0x1));
        reg.setRemoteAdapter(chainId, address(0x2));
        assertEq(reg.remoteAdapterOf(chainId), address(0x2));
    }
}
