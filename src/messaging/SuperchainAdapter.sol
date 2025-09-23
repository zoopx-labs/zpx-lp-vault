// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IL2ToL2CrossDomainMessenger} from "./interfaces/IL2ToL2CrossDomainMessenger.sol";
import {AdapterRegistry} from "./AdapterRegistry.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Superchain (L2->L2) adapter. Additive alongside existing MockAdapter.
///         No changes to upgradeable endpoint storage. Uses external registry for remote auth.
/// @dev    Cross-chain payload format: abi.encode(srcChainId, nonce, inner)
contract SuperchainAdapter is ReentrancyGuard {
    IL2ToL2CrossDomainMessenger public immutable messenger;
    AdapterRegistry public immutable registry;
    address public immutable endpoint; // MessagingEndpointReceiver (existing)
    address public immutable owner;

    uint64 public outboundNonce;
    bool public paused;

    mapping(bytes32 => bool) public used; // replay guard

    event Paused(bool status);
    event MessageSent(uint256 indexed destChainId, bytes inner, uint64 nonce);
    event MessageReceived(uint256 indexed srcChainId, bytes inner, uint64 nonce);
    event EndpointCallFailed(bytes inner);

    constructor(address _messenger, address _registry, address _endpoint) {
        require(_messenger != address(0) && _registry != address(0) && _endpoint != address(0), "ZERO_ADDR");
        messenger = IL2ToL2CrossDomainMessenger(_messenger);
        registry = AdapterRegistry(_registry);
        endpoint = _endpoint;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    function setPaused(bool p) external onlyOwner {
        paused = p;
        emit Paused(p);
    }

    function send(
        uint256 destChainId,
        bytes calldata inner,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external nonReentrant returns (uint64 nonce) {
        require(!paused, "PAUSED");
        address remoteAdapter = registry.remoteAdapterOf(destChainId);
        require(remoteAdapter != address(0), "NO_REMOTE");
        nonce = ++outboundNonce;
        bytes memory packed = abi.encode(block.chainid, nonce, inner);
        messenger.sendMessage(destChainId, remoteAdapter, packed, minGasLimit, extraData);
        emit MessageSent(destChainId, inner, nonce);
    }

    function onMessage(bytes calldata packed) external nonReentrant {
        require(msg.sender == address(messenger), "NOT_MESSENGER");
        (uint256 srcChainId, uint64 nonce, bytes memory inner) = abi.decode(packed, (uint256, uint64, bytes));
        address expectedRemote = registry.remoteAdapterOf(srcChainId);
        require(expectedRemote != address(0), "UNCONFIGURED_SRC");
        require(messenger.xDomainMessageSender() == expectedRemote, "BAD_REMOTE");
        bytes32 key = keccak256(packed);
        require(!used[key], "REPLAY");
        used[key] = true;
        (bool ok,) = endpoint.call(inner);
        if (!ok) emit EndpointCallFailed(inner);
        emit MessageReceived(srcChainId, inner, nonce);
    }
}
