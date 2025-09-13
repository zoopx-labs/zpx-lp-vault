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
        // BORROWER_ROLE should be granted to router
        bytes32 role = SpokeVault(v).BORROWER_ROLE();
        assertTrue(SpokeVault(v).hasRole(role, r));
    }
}
