// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
 * @title USDzy
 * @dev Upgradeable, non-rebasing share token. Mint/Burn restricted to roles (Hub).
 * Uses ERC20 + EIP-2612 permit.
 */
contract USDzy is
    Initializable,
    ContextUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    event Upgraded(address indexed who, address indexed newImpl);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(string memory name_, string memory symbol_, address admin) public initializer {
        require(admin != address(0), "admin zero");
        __Context_init_unchained();
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(BURNER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /**
     * @notice Mint shares to an account. Only callable by accounts with MINTER_ROLE (Hub).
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burn shares from an account. Only callable by accounts with BURNER_ROLE (Hub).
     */
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        emit Upgraded(msg.sender, newImplementation);
    }

    // Storage gap for upgradeability
    uint256[50] private __gap;
}
