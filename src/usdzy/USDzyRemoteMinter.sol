// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MessagingEndpointReceiver} from "../messaging/MessagingEndpointReceiver.sol";

interface IUSDzy {
    function mint(address to, uint256 amount) external;
}

contract USDzyRemoteMinter is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    MessagingEndpointReceiver
{
    address public usdzy;
    address public admin;

    function initialize(address usdzy_, address admin_) public initializer {
        usdzy = usdzy_;
        admin = admin_;
        __MessagingEndpointReceiver_init(admin_);
    }

    // onMessage called by MessagingAdapter in tests
    function onMessage(uint64 srcChainId, address srcAddr, bytes calldata payload, uint64 nonce) external {
        _verifyAndMark(srcChainId, srcAddr, payload, nonce);
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        IUSDzy(usdzy).mint(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
