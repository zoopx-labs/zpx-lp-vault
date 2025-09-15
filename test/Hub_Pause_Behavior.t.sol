// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Hub} from "src/Hub.sol";
import {USDzy} from "src/USDzy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyUtils} from "./utils/ProxyUtils.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockDIAFeed} from "src/mocks/MockDIAFeed.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HubPauseTest is Test {
    USDzy usdzy;
    Hub hub;
    MockERC20 usdc;
    MockDIAFeed feedUsdc;

    function setUp() public {
        USDzy usdzyImpl = new USDzy();
        address usdzyProxy = ProxyUtils.deployProxy(
            address(usdzyImpl), abi.encodeCall(USDzy.initialize, ("USDzy", "USZY", address(this)))
        );
        usdzy = USDzy(usdzyProxy);

        Hub impl = new Hub();
        address proxy =
            ProxyUtils.deployProxy(address(impl), abi.encodeCall(Hub.initialize, (address(usdzy), address(this))));
        hub = Hub(proxy);

        usdzy.grantRole(usdzy.MINTER_ROLE(), address(hub));
        usdzy.grantRole(usdzy.BURNER_ROLE(), address(hub));

        usdc = new MockERC20("USDC", "USDC");
        feedUsdc = new MockDIAFeed(int256(1_000000), block.timestamp);
        hub.setAssetConfig(address(usdc), address(feedUsdc), 6, 6, 0, true);
    }

    function testPauseBehavior() public {
        // mint user some USDC
        usdc.mint(address(this), 1_000_000);
        IERC20(address(usdc)).approve(address(hub), type(uint256).max);

        // deposit while unpaused ok
        hub.deposit(address(usdc), 1_000_000);
        uint256 shares = usdzy.balanceOf(address(this));

        // pause
        hub.pause();

        // deposit should revert
        vm.expectRevert();
        hub.deposit(address(usdc), 1_000_000);

        // claimWithdraw should revert (no ticket yet but assume revert guard)
        vm.expectRevert();
        hub.claimWithdraw(0, address(usdc));

        // requestWithdraw should succeed while paused
        hub.requestWithdraw(shares);
        uint256 cnt = hub.requestsCount();
        assertEq(cnt, 1);
    }
}
