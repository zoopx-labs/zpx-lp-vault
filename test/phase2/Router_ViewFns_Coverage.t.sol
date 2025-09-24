// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "src/router/Router.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockAdapter} from "src/messaging/MockAdapter.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

// This test is intentionally simple: it just exercises view functions that
// were previously showing 0 hits in filtered prod coverage (tvl, available,
// avg7d, healthBps) so their lines are counted. It also drives a snapshot
// update across multiple days to give avg7d a non-zero sum path.
contract RouterViewFnsCoverageTest is Test {
    Router router;
    SpokeVault vault;
    MockERC20 token;
    MockAdapter adapter;
    address admin = address(0xA11CE);

    function setUp() public {
        token = new MockERC20("Token", "TKN");
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", admin))
        );
        vault = SpokeVault(vProxy);
        adapter = new MockAdapter();
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl),
            abi.encodeCall(Router.initialize, (address(vault), address(adapter), admin, address(0xC0FFEE)))
        );
        router = Router(rProxy);
        vm.prank(admin);
        router.setAdapter(address(adapter));
    }

    function testViewFunctionsCoverage() public {
        // Initially TVL and available are zero
        assertEq(router.tvl(), 0, "tvl initial");
        assertEq(router.available(), 0, "available initial");
        // Populate snapshots over 3 days (ring buffer length is 7)
        for (uint256 i = 0; i < 3; i++) {
            router.pokeTvlSnapshot();
            vm.warp(block.timestamp + 1 days);
        }
        // avg7d should now be 0 still (no deposits) but the loop executed reading entries
        assertEq(router.avg7d(), 0, "avg7d zero");
        // healthBps on zero TVL returns max (65535)
        assertEq(router.healthBps(), 65535, "healthBps max when tvl=0");
    }
}
