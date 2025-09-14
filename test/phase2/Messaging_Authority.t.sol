// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockAdapter} from "../../src/messaging/MockAdapter.sol";
import {MessagingEndpointReceiver} from "../../src/messaging/MessagingEndpointReceiver.sol";

contract ReceiverForAuth is MessagingEndpointReceiver {
    address public lastTo;
    uint256 public lastAmt;

    constructor() {
        __MessagingEndpointReceiver_init(msg.sender);
    }

    function onMessage(uint64 srcChainId, address srcAddr, bytes calldata payload, uint64 nonce) external {
        // use the internal verifier which enforces adapter-authority and replay protection
        _verifyAndMark(srcChainId, srcAddr, payload, nonce);
        (address to, uint256 amt) = abi.decode(payload, (address, uint256));
        lastTo = to;
        lastAmt = amt;
    }
}

contract MessagingAuthorityTest is Test {
    MockAdapter adapter;
    ReceiverForAuth r;

    function setUp() public {
        adapter = new MockAdapter();
        r = new ReceiverForAuth();
        // register src endpoint as allowed by owner
        r.setEndpoint(1, address(adapter), true);
        // also allow the test caller (adapter.send will encode msg.sender as the test caller)
        r.setEndpoint(1, address(this), true);
    }

    function testAdapterMustBeCallerWhenAdapterSet() public {
        bytes memory payload = abi.encode(address(this), uint256(42));

        // set adapter on receiver (owner only)
        r.setAdapter(address(adapter));

        // direct call from srcAddr should fail because adapter is configured
        vm.prank(address(0xCAFE));
        vm.expectRevert(bytes("NOT_ADAPTER"));
        r.onMessage(1, address(0xCAFE), payload, 1);

        // calling via adapter should succeed
        uint64 n = adapter.send(1, address(r), payload);
        assertEq(n, 1);
        assertEq(r.lastTo(), address(this));
        assertEq(r.lastAmt(), 42);
    }
}
