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

        // implementations should be cached in Factory (calling deploy again should reuse impls)
        (address v2, address r2) = f.deploySpoke(
            uint64(block.chainid), address(0x1), "sv2", "sv2", address(this), address(this), address(0x2), address(0)
        );
        bytes32 implVSlot2 = vm.load(v2, implSlot);
        bytes32 implRSlot2 = vm.load(r2, implSlot);
        // impl slots should equal (same implementation used)
        assertEq(implVSlot, implVSlot2);
        assertEq(implRSlot, implRSlot2);

        // BORROWER_ROLE should be granted to router
        bytes32 role = SpokeVault(v).BORROWER_ROLE();
        assertTrue(SpokeVault(v).hasRole(role, r));

        // both should be paused by default
    // try unpause by intended admin (this test contract) - should succeed because Factory transferred roles
    SpokeVault(v).unpause();
    Router(r).unpause();

    // Factory should have renounced admin roles on deployed proxies
    // attempting to grant role as Factory (f) should revert; we simulate by calling hasRole for Factory should be false
    bytes32 adminRole = SpokeVault(v).DEFAULT_ADMIN_ROLE();
    assertFalse(SpokeVault(v).hasRole(adminRole, address(f)));
    assertFalse(Router(r).hasRole(Router(r).DEFAULT_ADMIN_ROLE(), address(f)));

    // Router should be initialized with provided feeCollector (address(0) was passed) and adapter set to provided adapter
    // adapter stored should equal address(0x2) per initializer call above
    // read adapter slot via public accessor
    // note: Router.adapter() returns IMessagingAdapter, compare as address
    assertEq(address(Router(r).adapter()), address(0x2));
    }
}
