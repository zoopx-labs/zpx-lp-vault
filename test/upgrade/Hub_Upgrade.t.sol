// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Hub} from "../../src/Hub.sol";
import {USDzy} from "../../src/USDzy.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";

contract HubUpgrade is Test {
    function testUpgradeHubKeepsState() public {
        address admin = address(this);
        // deploy USDzy via proxy (non-zero address required by Hub.initialize)
        USDzy usdzyImpl = new USDzy();
        address usdzyProxy =
            ProxyUtils.deployProxy(address(usdzyImpl), abi.encodeCall(USDzy.initialize, ("USDzy", "USZY", admin)));

        // deploy Hub via proxy and initialize
        Hub impl = new Hub();
        bytes memory init = abi.encodeCall(Hub.initialize, (address(usdzyProxy), admin));
        address proxy = ProxyUtils.deployProxy(address(impl), init);
        Hub hub = Hub(proxy);

        // set an asset config to create state
        address token = address(0x123);
        hub.setAssetConfig(token, address(0x0), 6, 6, 0, true);
        assertTrue(hub.isListed(token));

        // upgrade impl
        Hub impl2 = new Hub();
        // simulate upgrade by writing the ERC1967 implementation slot directly (eip1967)
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        vm.store(address(hub), implSlot, bytes32(uint256(uint160(address(impl2)))));

        // state preserved
        assertTrue(hub.isListed(token));
    }
}
