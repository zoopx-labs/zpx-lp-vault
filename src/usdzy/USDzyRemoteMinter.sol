// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MessagingEndpointReceiver} from "../messaging/MessagingEndpointReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDzy {
    function mint(address to, uint256 amount) external;
}

contract USDzyRemoteMinter is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    MessagingEndpointReceiver
{
    address public usdzy;
    bytes32 public constant GATEWAY_ROLE = keccak256("GATEWAY_ROLE");

    event GatewayMinted(address indexed to, uint256 shares);

    function initialize(address usdzy_, address admin_) public initializer {
        __MessagingEndpointReceiver_init(address(0)); // will be set by admin
        __UUPSUpgradeable_init();

        usdzy = usdzy_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    function mintFromGateway(address to, uint256 shares) external onlyRole(GATEWAY_ROLE) whenNotPaused nonReentrant {
        IUSDzy(usdzy).mint(to, shares);
        emit GatewayMinted(to, shares);
    }

    function onMessage(uint64 srcChainId, address srcAddr, bytes calldata payload, uint64 nonce)
        external
        nonReentrant
    {
        _verifyAndMark(srcChainId, srcAddr, payload, nonce);
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        IUSDzy(usdzy).mint(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
