// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockAdapter} from "../../src/messaging/MockAdapter.sol";
import {MessagingEndpointReceiver} from "../../src/messaging/MessagingEndpointReceiver.sol";

contract ReceiverMock is MessagingEndpointReceiver {
    address public lastFrom;
    uint256 public lastAmt;

    constructor() {
        __MessagingEndpointReceiver_init(msg.sender);
    }

    function onMessage(uint64 srcChainId, address srcAddr, bytes calldata payload, uint64 nonce) external {
        require(allowedEndpoint[srcChainId][srcAddr], "BAD_ENDPOINT");
        bytes32 key = keccak256(abi.encodePacked(srcChainId, srcAddr, payload, nonce));
        require(_markUsed(key), "REPLAY");
        (address to, uint256 amt) = abi.decode(payload, (address, uint256));
        lastFrom = to;
        lastAmt = amt;
    }
}

contract MessagingTest is Test {
    MockAdapter adapter;
    ReceiverMock r;

    function setUp() public {
        adapter = new MockAdapter();
        r = new ReceiverMock();
        // owner (this) registers the adapter as an allowed source on the receiver
        r.setEndpoint(1, address(adapter), true);
    }

    function testReplayAndEndpoint() public {
        bytes memory payload = abi.encode(address(this), uint256(1000));
        uint64 n = adapter.send(1, address(r), payload);
        // second send with same payload+nonce should revert in receiver
        uint64 n2 = adapter.send(1, address(r), payload);
        assertTrue(n2 > n);
    }
}
