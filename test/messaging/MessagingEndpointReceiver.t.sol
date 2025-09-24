// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MessagingEndpointReceiver} from "src/messaging/MessagingEndpointReceiver.sol";
import {IMessagingAdapter} from "src/interfaces/IMessagingAdapter.sol";

// Minimal mock adapter to invoke onMessage-like flow
contract MockAdapter is IMessagingAdapter {
    address public endpoint;

    constructor(address e) {
        endpoint = e;
    }

    function send(uint64, address, bytes calldata) external pure returns (uint64) {
        return 0;
    }
}

// Expose internal initializer + internal verify via a helper wrapper
contract Wrapper is MessagingEndpointReceiver {
    function init(address o) external {
        __MessagingEndpointReceiver_init(o);
    }

    function verifyPublic(uint64 c, address a, bytes calldata p, uint64 n) external returns (bytes32) {
        return _verifyAndMark(c, a, p, n);
    }
}

contract MessagingEndpointReceiverTest is Test {
    MessagingEndpointReceiver recv;
    MockAdapter adapter;
    address owner = address(this);
    address srcAddr = address(0xBEEF);
    uint64 srcChain = 10; // OP
    Wrapper wrap;

    function setUp() public {
        wrap = new Wrapper();
        wrap.init(owner);
        recv = MessagingEndpointReceiver(address(wrap));
        // legacy path: no adapter yet. allow direct endpoint
        recv.setEndpoint(srcChain, srcAddr, true); // owner call
    }

    function test_legacy_success_and_replay_and_badSender() public {
        bytes memory payload = abi.encode("PING");
        // success first time (caller == srcAddr)
        vm.prank(srcAddr);
        bytes32 key = wrap.verifyPublic(srcChain, srcAddr, payload, 1);
        assertTrue(key != bytes32(0));
        // replay with same nonce should revert
        vm.prank(srcAddr);
        vm.expectRevert(bytes("REPLAY"));
        wrap.verifyPublic(srcChain, srcAddr, payload, 1);
        // wrong caller
        vm.expectRevert(bytes("BAD_SENDER"));
        wrap.verifyPublic(srcChain, srcAddr, payload, 2);
    }

    function test_legacy_badEndpointReverts() public {
        // remove allowance
        recv.setEndpoint(srcChain, srcAddr, false);
        vm.prank(srcAddr);
        vm.expectRevert(bytes("BAD_ENDPOINT"));
        wrap.verifyPublic(srcChain, srcAddr, abi.encode("X"), 1);
    }

    function test_adapter_mode_checks_NOT_ADAPTER_and_BAD_ENDPOINT() public {
        // configure adapter
        adapter = new MockAdapter(address(recv));
        recv.setAdapter(address(adapter));
        // mark endpoint allowed via adapter call (simulate adapter registering)
        vm.prank(address(adapter));
        recv.setEndpoint(srcChain, srcAddr, true);
        bytes memory payload = abi.encode("HELLO");
        // call via adapter (should succeed)
        vm.prank(address(adapter));
        wrap.verifyPublic(srcChain, srcAddr, payload, 1);
        // non-adapter caller now reverts NOT_ADAPTER
        vm.expectRevert(bytes("NOT_ADAPTER"));
        wrap.verifyPublic(srcChain, srcAddr, payload, 2);
        // adapter caller but endpoint removed -> BAD_ENDPOINT
        vm.prank(address(adapter));
        recv.setEndpoint(srcChain, srcAddr, false);
        vm.prank(address(adapter));
        vm.expectRevert(bytes("BAD_ENDPOINT"));
        wrap.verifyPublic(srcChain, srcAddr, payload, 3);
    }

    function test_setEndpoint_not_authorized_after_adapter_set() public {
        adapter = new MockAdapter(address(recv));
        recv.setAdapter(address(adapter));
        // a random address should not be able to call setEndpoint now (only owner or adapter)
        address rand = address(0xDEAD);
        vm.prank(rand);
        vm.expectRevert(bytes("NOT_AUTHORIZED"));
        recv.setEndpoint(srcChain, address(0xABCD), true);
    }
}
