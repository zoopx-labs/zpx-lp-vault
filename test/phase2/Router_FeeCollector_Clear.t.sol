// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "src/router/Router.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

// Covers branch allowing feeCollector to be cleared only when protocolFeeBps == 0
contract RouterFeeCollectorClearTest is Test {
    Router router;
    SpokeVault vault;
    MockERC20 token;
    address admin = address(0xA11CE);
    address collector = address(0xD00D);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN");
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", admin))
        );
        vault = SpokeVault(vProxy);
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl), abi.encodeCall(Router.initialize, (address(vault), address(0x1), admin, collector))
        );
        router = Router(rProxy);
    }

    function testClearFeeCollectorWhenProtocolFeeZero() public {
        // protocolFeeBps is zero by default so clearing collector should succeed
        vm.prank(admin);
        router.setFeeCollector(address(0));
        assertEq(router.feeCollector(), address(0));

        // now set protocol fee >0 and attempt to clear again should fail
        vm.prank(admin);
        router.setProtocolFeeBps(5);
        vm.prank(admin);
        vm.expectRevert(bytes("FeeCollector=0"));
        router.setFeeCollector(address(0));
    }
}
