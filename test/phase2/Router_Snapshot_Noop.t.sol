// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "src/router/Router.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

// Covers early return branch in pokeTvlSnapshot when called twice in same day
contract RouterSnapshotNoopTest is Test {
    Router router;
    SpokeVault vault;
    MockERC20 token;
    address admin = address(0xA11CE);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN");
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", admin))
        );
        vault = SpokeVault(vProxy);
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl), abi.encodeCall(Router.initialize, (address(vault), address(0x1), admin, address(0xC0FFEE)))
        );
        router = Router(rProxy);
        // seed some TVL
        token.mint(address(vault), 1_000e18);
    }

    function testSnapshotNoopSameDay() public {
        router.pokeTvlSnapshot();
        uint64 lastDay = router.lastSnapDay();
        uint8 idxBefore = router.idx();
        // second call same day should early return without changing idx or lastSnapDay
        router.pokeTvlSnapshot();
        assertEq(router.lastSnapDay(), lastDay, "day unchanged");
        assertEq(router.idx(), idxBefore, "index unchanged");
    }
}
