// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IL2ToL2CrossDomainMessenger {
    function sendMessage(
        uint256 destChainId,
        address target,
        bytes calldata message,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external payable;

    function xDomainMessageSender() external view returns (address);
}
