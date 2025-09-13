// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Factory} from "../../src/factory/Factory.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {Router} from "../../src/router/Router.sol";

contract FactorySmoke is Test {
    Factory f;

    function setUp() public {
        f = new Factory();
        f.initialize(address(this));
    }

    function testDeploySpokeCreatesProxiesAndWiresRoles() public {
        // first deploy implementation contracts and register them
        address implV = address(new SpokeVault());
        address implR = address(new Router());
        f.setSpokeVaultImpl(implV);
        f.setRouterImpl(implR);



        (address v, address r) = f.deploySpoke(
            uint64(block.chainid), address(0x1), "sv", "sv", address(this), address(this), address(0x2), address(0)
        );
    // ensure deployed addresses are contracts
        uint256 sizeV;
        uint256 sizeR;
        assembly {
            sizeV := extcodesize(v)
        }
        assembly {
            sizeR := extcodesize(r)
        }
        assertGt(sizeV, 0);
        assertGt(sizeR, 0);
    // implementation slot should be nonzero
    bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    bytes32 implVSlot = vm.load(v, implSlot);
    bytes32 implRSlot = vm.load(r, implSlot);
    assertTrue(implVSlot != bytes32(0));
    assertTrue(implRSlot != bytes32(0));

    // BORROWER_ROLE should be granted to router
    bytes32 role = SpokeVault(v).BORROWER_ROLE();
    assertTrue(SpokeVault(v).hasRole(role, r));

    // both should be paused by default
    // calling deposit or fill should revert due to paused; we just check pause/unpause via Pausable
    // SpokeVault paused -> pause() would revert for non-pauser, but isPaused exposed via low-level call
    // instead, check that unpause by admin succeeds
    SpokeVault(v).unpause();
    Router(r).unpause();
    }
}


