// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {USDzyRemoteMinter} from "src/usdzy/USDzyRemoteMinter.sol";
import {USDzy} from "src/USDzy.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MessagingEndpointReceiver} from "src/messaging/MessagingEndpointReceiver.sol";

// Lightweight mock adapter to exercise adapter-set path
contract MockAdapterForMinter {
    USDzyRemoteMinter public minter;

    constructor(USDzyRemoteMinter m) {
        minter = m;
    }
    // simulate adapter delivering a message

    function deliver(uint64 srcChain, address srcEndpoint, address to, uint256 amt, uint64 nonce) external {
        bytes memory payload = abi.encode(to, amt);
        // craft low-level call matching onMessage signature
        minter.onMessage(srcChain, srcEndpoint, payload, nonce);
    }
}

contract USDzyRemoteMinterPositiveTest is Test {
    USDzy usdzy;
    USDzyRemoteMinter minter;
    MockAdapterForMinter adapter;
    address admin = address(0xA11CE);
    address gateway = address(0xBEEF);

    function setUp() public {
        // deploy USDzy proxy
        USDzy implZ = new USDzy();
        address pZ = ProxyUtils.deployProxy(address(implZ), abi.encodeCall(USDzy.initialize, ("USDzy", "USZY", admin)));
        usdzy = USDzy(pZ);

        // deploy remote minter proxy
        USDzyRemoteMinter impl = new USDzyRemoteMinter();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(USDzyRemoteMinter.initialize, (address(usdzy), admin)));
        minter = USDzyRemoteMinter(address(proxy));

        // grant roles (admin is the configured admin in initialize)
        vm.startPrank(admin);
        usdzy.grantRole(usdzy.MINTER_ROLE(), address(minter));
        minter.grantRole(minter.GATEWAY_ROLE(), gateway);
        vm.stopPrank();

        adapter = new MockAdapterForMinter(minter);
        // owner sets adapter (owner is admin passed in initialize)
        vm.startPrank(admin);
        minter.setAdapter(address(adapter));
        // allow source endpoint (gateway contract address placeholder) on a source chain id
        minter.setEndpoint(uint64(777), gateway, true);
        vm.stopPrank();
    }

    function test_mintFromGateway_directRole() public {
        // caller has GATEWAY_ROLE -> direct mint path
        vm.prank(gateway);
        minter.mintFromGateway(address(this), 500);
        assertEq(usdzy.balanceOf(address(this)), 500, "minted shares");
    }

    function test_onMessage_adapterPath_and_replayGuard() public {
        // adapter-set path: only adapter may call onMessage via deliver()
        // first delivery
        adapter.deliver(777, gateway, address(this), 1000, 1);
        assertEq(usdzy.balanceOf(address(this)), 1000, "first mint");
        // second different nonce
        adapter.deliver(777, gateway, address(this), 2000, 2);
        assertEq(usdzy.balanceOf(address(this)), 3000, "accumulated mint");
        // replay (same nonce/payload) should revert REPLAY
        vm.expectRevert("REPLAY");
        adapter.deliver(777, gateway, address(this), 2000, 2);
    }

    function test_onMessage_badEndpointReverts() public {
        // endpoint not allowed -> BAD_ENDPOINT
        vm.expectRevert("BAD_ENDPOINT");
        adapter.deliver(888, gateway, address(this), 1, 1); // unconfigured chain id
    }

    function test_onMessage_wrongAdapterReverts() public {
        // When adapter is set, only adapter can call. Simulate direct call from non-adapter.
        bytes memory payload = abi.encode(address(this), uint256(1));
        // direct prank as gateway (not adapter) should revert NOT_ADAPTER
        vm.expectRevert("NOT_ADAPTER");
        vm.prank(gateway);
        minter.onMessage(777, gateway, payload, 9);
    }
}
