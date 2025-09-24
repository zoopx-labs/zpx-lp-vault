// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MessagingEndpointReceiver} from "src/messaging/MessagingEndpointReceiver.sol";
import {IMessagingAdapter} from "src/interfaces/IMessagingAdapter.sol";

// Minimal adapter mock to test onlyAdapter modifier path (NOT_ADAPTER & NO_ADAPTER branches)
contract MockAdapterOnly is IMessagingAdapter {
    function send(uint64, address, bytes calldata) external pure returns (uint64) {
        return 0;
    }
}

contract WrapperOnly is MessagingEndpointReceiver {
    function init(address owner_) external {
        __MessagingEndpointReceiver_init(owner_);
    }
    // expose modifier usage via a function restricted to onlyAdapter

    function onlyAdapterFn() external onlyAdapter returns (uint256) {
        return 1;
    }
}

contract MessagingEndpointReceiverAdapterOnlyTest is Test {
    WrapperOnly wrap;
    MockAdapterOnly adapter;

    function setUp() public {
        wrap = new WrapperOnly();
        wrap.init(address(this));
    }

    function test_onlyAdapter_reverts_when_no_adapter_set() public {
        // adapter not set -> onlyAdapter should revert with NO_ADAPTER
        vm.expectRevert(bytes("NO_ADAPTER"));
        wrap.onlyAdapterFn();
    }

    function test_onlyAdapter_success_and_not_adapter_revert() public {
        adapter = new MockAdapterOnly();
        wrap.setAdapter(address(adapter));
        // call via adapter OK
        vm.prank(address(adapter));
        uint256 r = wrap.onlyAdapterFn();
        assertEq(r, 1);
        // non-adapter caller now reverts NOT_ADAPTER
        vm.expectRevert(bytes("NOT_ADAPTER"));
        wrap.onlyAdapterFn();
    }
}
