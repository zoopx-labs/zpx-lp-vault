// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract AdapterRegistry {
    address public immutable owner;
    mapping(uint256 => address) private _remoteAdapter;

    event RemoteAdapterSet(uint256 indexed chainId, address indexed adapter);

    constructor() {
        owner = msg.sender;
    }

    function setRemoteAdapter(uint256 chainId, address adapter) external {
        require(msg.sender == owner, "NOT_OWNER");
        _remoteAdapter[chainId] = adapter;
        emit RemoteAdapterSet(chainId, adapter);
    }

    function remoteAdapterOf(uint256 chainId) external view returns (address) {
        return _remoteAdapter[chainId];
    }
}
