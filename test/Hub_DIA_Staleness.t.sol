// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Hub} from "src/Hub.sol";
import {USDzy} from "src/USDzy.sol";
import {ProxyUtils} from "./utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockDIAFeed} from "src/mocks/MockDIAFeed.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DIASlatenessTest is Test {
    USDzy usdzy;
    Hub hub;
    MockERC20 token;
    MockDIAFeed feed;

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

        token = new MockERC20("TKN", "TKN");
        // ensure we can create a safely-old timestamp without underflow in foundry's initial block timestamp
        vm.warp(2000);
        feed = new MockDIAFeed(int256(1_000000), block.timestamp - 1000); // old
        hub.setAssetConfig(address(token), address(feed), 18, 6, 0, true);
    }

    function testDepositRevertsWhenStale() public {
        token.mint(address(this), 1e18);
        IERC20(address(token)).approve(address(hub), type(uint256).max);
        vm.expectRevert();
        hub.deposit(address(token), 1e18);
    }

    function testClaimRevertsWhenStale() public {
        // set a fresh feed first and deposit
        feed.set(int256(1_000000), block.timestamp);
        token.mint(address(this), 1e18);
        IERC20(address(token)).approve(address(hub), type(uint256).max);
        hub.deposit(address(token), 1e18);
        uint256 shares = usdzy.balanceOf(address(this));
        hub.requestWithdraw(shares);
        vm.warp(block.timestamp + 2 hours + 1);
        // make feed stale
        feed.set(int256(1_000000), block.timestamp - 1000);
        vm.expectRevert();
        hub.claimWithdraw(0, address(token));
    }
}
