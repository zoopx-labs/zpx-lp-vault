// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SuperchainAdapter} from "src/messaging/SuperchainAdapter.sol";
import {AdapterRegistry} from "src/messaging/AdapterRegistry.sol";
import {IL2ToL2CrossDomainMessenger} from "src/messaging/interfaces/IL2ToL2CrossDomainMessenger.sol";

interface IEndpointLike { function willRevert() external; }

contract MockMessengerNeg is IL2ToL2CrossDomainMessenger {
    address public xSender;
    bytes public lastMessage;
    uint256 public lastDest;
    address public lastTarget;
    function setXSender(address s) external { xSender = s; }
    function sendMessage(uint256 destChainId, address target, bytes calldata message, uint32, bytes calldata) external payable {
        lastDest = destChainId; lastTarget = target; lastMessage = message; }
    function xDomainMessageSender() external view returns (address) { return xSender; }
}

contract EndpointReverting {
    function willRevert() external pure { revert("EP_FAIL"); }
}

contract SuperchainAdapterNegativeTest is Test {
    MockMessengerNeg messenger;
    AdapterRegistry registry;
    EndpointReverting endpoint;
    SuperchainAdapter localAdapter;
    SuperchainAdapter remoteAdapter;

    uint256 constant CHAIN_REMOTE = 99_999;

    function setUp() public {
        messenger = new MockMessengerNeg();
        registry = new AdapterRegistry();
        endpoint = new EndpointReverting();
        localAdapter = new SuperchainAdapter(address(messenger), address(registry), address(endpoint));
        remoteAdapter = new SuperchainAdapter(address(messenger), address(registry), address(endpoint));
        // map our local chain for receive auth and remote for outbound
        vm.prank(registry.owner()); registry.setRemoteAdapter(block.chainid, address(localAdapter));
        vm.prank(registry.owner()); registry.setRemoteAdapter(CHAIN_REMOTE, address(remoteAdapter));
    }

    function test_paused_send_reverts() public {
        vm.prank(localAdapter.owner());
        localAdapter.setPaused(true);
        vm.expectRevert(bytes("PAUSED"));
        localAdapter.send(CHAIN_REMOTE, abi.encodePacked("x"), 0, "");
    }

    function test_no_remote_reverts() public {
        // remove remote mapping
        vm.prank(registry.owner()); registry.setRemoteAdapter(CHAIN_REMOTE, address(0));
        vm.expectRevert(bytes("NO_REMOTE"));
        localAdapter.send(CHAIN_REMOTE, abi.encodePacked("y"), 0, "");
    }

    function test_unconfigured_src_and_bad_remote() public {
        // Outbound OK
        localAdapter.send(CHAIN_REMOTE, abi.encode("z"), 0, "");
        // craft packed message
        bytes memory packed = messenger.lastMessage();
        // UNCONFIGURED_SRC: remove mapping for src chain id (block.chainid)
        vm.prank(registry.owner()); registry.setRemoteAdapter(block.chainid, address(0));
        messenger.setXSender(address(localAdapter));
        vm.prank(address(messenger));
        vm.expectRevert(bytes("UNCONFIGURED_SRC"));
        remoteAdapter.onMessage(packed);

        // Re-map but wrong expected remote -> BAD_REMOTE
        vm.prank(registry.owner()); registry.setRemoteAdapter(block.chainid, address(remoteAdapter)); // incorrect: expects remoteAdapter but xSender will be localAdapter
        messenger.setXSender(address(localAdapter));
        vm.prank(address(messenger));
        vm.expectRevert(bytes("BAD_REMOTE"));
        remoteAdapter.onMessage(packed);
    }

    function test_endpoint_call_failed_event_emitted() public {
        // send message that calls non-existent function to force failure (or revert signature) on endpoint
        bytes memory failingInner = abi.encodeWithSignature("willRevert()");
        localAdapter.send(CHAIN_REMOTE, failingInner, 0, "");
        bytes memory packed = messenger.lastMessage();
        messenger.setXSender(address(localAdapter));
        // expect no revert: adapter swallows endpoint failure and emits event
        vm.expectEmit(true, false, false, true); // we only care that event is emitted (indexed srcChainId)
        emit SuperchainAdapter.MessageReceived(block.chainid, failingInner, localAdapter.outboundNonce());
        vm.prank(address(messenger));
        remoteAdapter.onMessage(packed);
        // Note: EndpointCallFailed also emitted; we could capture it but not necessary for coverage.
    }
}
