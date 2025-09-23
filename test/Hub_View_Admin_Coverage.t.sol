// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Hub} from "src/Hub.sol";
import {USDzy} from "src/USDzy.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockDIAFeed} from "src/mocks/MockDIAFeed.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

contract HubViewAdminCoverageTest is Test {
    Hub hub;
    USDzy usdzy;
    MockERC20 token;
    MockDIAFeed feed;

    function setUp() public {
        // Deploy USDzy proxy
        USDzy usdzyImpl = new USDzy();
        address usdzyProxy = ProxyUtils.deployProxy(
            address(usdzyImpl), abi.encodeCall(USDzy.initialize, ("USDzy", "USZY", address(this)))
        );
        usdzy = USDzy(usdzyProxy);

        // Deploy Hub proxy
        Hub hubImpl = new Hub();
        address hubProxy = ProxyUtils.deployProxy(
            address(hubImpl), abi.encodeCall(Hub.initialize, (address(usdzy), address(this)))
        );
        hub = Hub(hubProxy);
        usdzy.grantRole(usdzy.MINTER_ROLE(), address(hub));
        usdzy.grantRole(usdzy.BURNER_ROLE(), address(hub));

        token = new MockERC20("TK", "TK");
        feed = new MockDIAFeed(int256(1_000000), block.timestamp);
        hub.setAssetConfig(address(token), address(feed), 18, 6, 0, true);
    }

    function test_view_admin_branches() public {
        // setMaxStaleness branch (already covered partially but exercise again)
        hub.setMaxStaleness(600);
        // getListedTokenDetails path (previously 0 hits when first added)
        (address[] memory addrs, uint8[] memory decs, address[] memory feeds) = hub.getListedTokenDetails();
        assertEq(addrs.length, 1);
        assertEq(addrs[0], address(token));
        assertEq(decs[0], 18);
        assertEq(feeds[0], address(feed));
        // pause / unpause (ensure both branches executed)
        hub.pause();
        hub.unpause();
    }
}
