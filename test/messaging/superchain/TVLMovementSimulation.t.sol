// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SuperchainAdapter} from "src/messaging/SuperchainAdapter.sol";
import {AdapterRegistry} from "src/messaging/AdapterRegistry.sol";
import {IL2ToL2CrossDomainMessenger} from "src/messaging/interfaces/IL2ToL2CrossDomainMessenger.sol";

// This simulation abstracts TVL movement with a single shared endpoint representing logical shared state.
contract MockMessenger2 is IL2ToL2CrossDomainMessenger {
    address public xSender;
    struct Pending {
        uint256 destChainId;
        address target;
        bytes message;
        uint32 gasLimit;
        bytes extra;
        address originalSender; // adapter on source chain
    }
    Pending[] public queue;

    function xDomainMessageSender() external view returns (address) { return xSender; }

    function sendMessage(
        uint256 destChainId,
        address target,
        bytes calldata message,
        uint32 gasLimit,
        bytes calldata extraData
    ) external payable {
        queue.push(Pending(destChainId, target, message, gasLimit, extraData, msg.sender));
    }

    function flush(uint256 idx) external {
        Pending memory p = queue[idx];
        xSender = p.originalSender; // mimic messenger reporting source adapter
        SuperchainAdapter(p.target).onMessage(p.message);
    }

    // test helper to override sender
    function setXSender(address sender_) external { xSender = sender_; }
}

contract PseudoVaultEndpoint {
    mapping(uint256 => uint256) public chainBalances; // chainId => simulated TVL
    event BalanceMoved(uint256 fromChain, uint256 toChain, uint256 amount);
    event Seeded(uint256 chainId, uint256 amount);

    function seed(uint256 chainId, uint256 amount) external {
        chainBalances[chainId] += amount;
        emit Seeded(chainId, amount);
    }

    function moveTVL(uint256 fromChain, uint256 toChain, uint256 amount) external {
        require(chainBalances[fromChain] >= amount, "insufficient");
        chainBalances[fromChain] -= amount;
        chainBalances[toChain] += amount;
        emit BalanceMoved(fromChain, toChain, amount);
    }
}

contract TVLMovementSimulationTest is Test {
    MockMessenger2 messenger;
    AdapterRegistry registry;
    PseudoVaultEndpoint endpoint;
    SuperchainAdapter baseAdapter; // Base
    SuperchainAdapter opAdapter;   // Optimism (placeholder id)
    SuperchainAdapter celoAdapter; // Celo (placeholder id)

    uint256 constant BASE = 8453;
    uint256 constant OP = 10_420; // placeholder id for test environment
    uint256 constant CELO = 42_000; // placeholder id for test environment

    function setUp() public {
        if (vm.envOr("SUPERCHAIN_TEST", uint256(0)) == 0) {
            vm.skip(true);
        }
        messenger = new MockMessenger2();
        registry = new AdapterRegistry();
        endpoint = new PseudoVaultEndpoint();
        baseAdapter = new SuperchainAdapter(address(messenger), address(registry), address(endpoint));
        opAdapter   = new SuperchainAdapter(address(messenger), address(registry), address(endpoint));
        celoAdapter = new SuperchainAdapter(address(messenger), address(registry), address(endpoint));
        vm.startPrank(registry.owner());
        registry.setRemoteAdapter(OP, address(opAdapter));
        registry.setRemoteAdapter(BASE, address(baseAdapter));
        registry.setRemoteAdapter(CELO, address(celoAdapter));
        // map local chain id as well for inbound auth when simulating from this chain
        registry.setRemoteAdapter(block.chainid, address(baseAdapter));
        vm.stopPrank();
    }

    function _encodeMove(uint256 fromChain, uint256 toChain, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(PseudoVaultEndpoint.moveTVL.selector, fromChain, toChain, amount);
    }

    function test_tvl_movement_across_chains() public {
        uint256 amount1 = 250_000 ether; // Base -> OP
        uint256 amount2 = 100_000 ether; // OP -> CELO

    // Initial seed (only once)
    endpoint.seed(BASE, 1_000_000 ether);

        // Base -> OP
        baseAdapter.send(OP, _encodeMove(BASE, OP, amount1), 0, "");
        messenger.flush(0); // deliver first message to OP adapter (moves TVL)
        assertEq(endpoint.chainBalances(BASE), 1_000_000 ether - amount1, "Base after first hop");
        assertEq(endpoint.chainBalances(OP), amount1, "OP after first hop");

    // OP -> CELO (manually fabricate cross-chain packet since block.chainid cannot change in single EVM context)
    bytes memory inner2 = _encodeMove(OP, CELO, amount2);
    // fabricate packet: (srcChainId=OP, nonce=1, inner2)
    bytes memory packet2 = abi.encode(OP, uint64(1), inner2);
    messenger.setXSender(address(opAdapter));
    vm.prank(address(messenger));
    celoAdapter.onMessage(packet2);
        assertEq(endpoint.chainBalances(OP), amount1 - amount2, "OP after second hop");
        assertEq(endpoint.chainBalances(CELO), amount2, "CELO after second hop");

        // Replay guard on first packet
        vm.expectRevert("REPLAY");
        messenger.flush(0);
    }
}
