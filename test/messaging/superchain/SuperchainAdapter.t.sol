// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SuperchainAdapter} from "src/messaging/SuperchainAdapter.sol";
import {AdapterRegistry} from "src/messaging/AdapterRegistry.sol";
import {IL2ToL2CrossDomainMessenger} from "src/messaging/interfaces/IL2ToL2CrossDomainMessenger.sol";

contract MockMessenger is IL2ToL2CrossDomainMessenger {
    address public lastTarget;
    bytes public lastMessage;
    uint256 public lastDest;
    uint32 public lastGas;
    bytes public lastExtra;
    address public xSender;

    function setXSender(address s) external { xSender = s; }

    function sendMessage(
        uint256 destChainId,
        address target,
        bytes calldata message,
        uint32 gasLimit,
        bytes calldata extraData
    ) external payable {
        lastDest = destChainId;
        lastTarget = target;
        lastMessage = message;
        lastGas = gasLimit;
        lastExtra = extraData;
    }

    function xDomainMessageSender() external view returns (address) {
        return xSender;
    }
}

contract DummyEndpoint {
    event DummyCalled(bytes data);
    uint256 public calls;
    bytes public last;
    function echo(bytes calldata data) external {
        calls++;
        last = data;
        emit DummyCalled(data);
    }
}

contract SuperchainAdapterTest is Test {
    MockMessenger messenger;
    AdapterRegistry registry;
    DummyEndpoint endpoint;
    SuperchainAdapter adapterA; // local source adapter
    SuperchainAdapter adapterB; // remote dest adapter

    uint256 constant CHAIN_B = 10_420;    // remote chain id example

    function setUp() public {
        if (vm.envOr("SUPERCHAIN_TEST", uint256(0)) == 0) {
            vm.skip(true);
        }
        messenger = new MockMessenger();
        registry = new AdapterRegistry();
        endpoint = new DummyEndpoint();
        adapterA = new SuperchainAdapter(address(messenger), address(registry), address(endpoint));
        adapterB = new SuperchainAdapter(address(messenger), address(registry), address(endpoint));
        // map dest chain id -> its adapter
        vm.prank(registry.owner());
        registry.setRemoteAdapter(CHAIN_B, address(adapterB));
        // map local (current) chain id -> source adapter (for receive auth)
        vm.prank(registry.owner());
        registry.setRemoteAdapter(block.chainid, address(adapterA));
    }

    function test_send_and_receive() public {
        bytes memory inner = abi.encodeWithSignature("echo(bytes)", bytes("ping"));
        adapterA.send(CHAIN_B, inner, 300000, "");
        // messenger slots contain packed payload
        messenger.setXSender(address(adapterA));
        bytes memory packed = messenger.lastMessage();
        vm.prank(address(messenger));
        adapterB.onMessage(packed);
        assertEq(endpoint.calls(), 1, "endpoint not invoked");
        // endpoint.last holds the argument actually passed to echo(bytes) which decodes to bytes("ping")
        bytes memory echoedArg = DummyEndpoint(address(endpoint)).last();
        assertEq(keccak256(echoedArg), keccak256(bytes("ping")), "echo payload mismatch");
    }

    function test_replay_guard() public {
        bytes memory inner = abi.encodeWithSignature("echo(bytes)", bytes("x"));
        adapterA.send(CHAIN_B, inner, 0, "");
        messenger.setXSender(address(adapterA));
        bytes memory packed = messenger.lastMessage();
        vm.prank(address(messenger));
        adapterB.onMessage(packed);
        vm.expectRevert("REPLAY");
        vm.prank(address(messenger));
        adapterB.onMessage(packed);
    }
}
