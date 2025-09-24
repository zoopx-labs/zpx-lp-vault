// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Hub} from "src/Hub.sol";
import {USDzy} from "src/USDzy.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockDIAFeed} from "src/mocks/MockDIAFeed.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HubEdgeCaseTest is Test {
    USDzy usdzy;
    Hub hub;
    MockERC20 token; // primary asset
    MockDIAFeed feed;
    MockERC20 token2; // secondary asset (no liquidity)
    MockDIAFeed feed2;

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
        token = new MockERC20("TK", "TK");
        feed = new MockDIAFeed(int256(1_000000), block.timestamp);
        hub.setAssetConfig(address(token), address(feed), 18, 6, 0, true);
        token2 = new MockERC20("TK2", "TK2");
        feed2 = new MockDIAFeed(int256(1_000000), block.timestamp);
        hub.setAssetConfig(address(token2), address(feed2), 18, 6, 0, true);
    }

    function test_setWithdrawDelay_and_NoFeed_and_badPrice() public {
        hub.setWithdrawDelay(1234);
        address unknown = address(0xABCD);
        vm.expectRevert();
        hub.quoteUsd6(unknown, 1, true);
        feed.set(int256(0), block.timestamp);
        vm.expectRevert(bytes("bad price"));
        hub.quoteUsd6(address(token), 1, true);
    }

    function test_requestWithdraw_zero_revert() public {
        vm.expectRevert(bytes("zero"));
        hub.requestWithdraw(0);
    }

    function test_claim_not_ready_revert() public {
        token.mint(address(this), 1e18);
        IERC20(address(token)).approve(address(hub), type(uint256).max);
        hub.deposit(address(token), 1e18);
        uint256 shares = usdzy.balanceOf(address(this));
        hub.requestWithdraw(shares);
        vm.expectRevert(bytes("not ready"));
        hub.claimWithdraw(0, address(token));
    }

    function test_claim_asset_disabled_revert() public {
        token.mint(address(this), 1e18);
        IERC20(address(token)).approve(address(hub), type(uint256).max);
        hub.deposit(address(token), 1e18);
        uint256 shares = usdzy.balanceOf(address(this));
        hub.requestWithdraw(shares);
        vm.warp(block.timestamp + 2 hours + 1);
        hub.setAssetConfig(address(token), address(feed), 18, 6, 0, false);
        vm.expectRevert(bytes("asset disabled"));
        hub.claimWithdraw(0, address(token));
    }

    function test_claim_stale_price_revert() public {
        token.mint(address(this), 1e18);
        IERC20(address(token)).approve(address(hub), type(uint256).max);
        hub.deposit(address(token), 1e18);
        uint256 shares = usdzy.balanceOf(address(this));
        hub.requestWithdraw(shares);
        vm.warp(block.timestamp + 2 hours + 1);
        // After the warp the original feed timestamp (setUp's initial block time) is now > maxStaleness old,
        // so claim should revert with StalePrice. We don't manually set an older timestamp to avoid
        // underflow when the current block time is less than the chosen subtraction delta in early blocks.
        vm.expectRevert(); // StalePrice custom error (arguments not asserted for simplicity)
        hub.claimWithdraw(0, address(token));
    }

    function test_claim_insufficient_liquidity_revert_with_alt_asset() public {
        // Deposit token to mint shares
        token.mint(address(this), 1e18);
        IERC20(address(token)).approve(address(hub), type(uint256).max);
        hub.deposit(address(token), 1e18);
        uint256 shares = usdzy.balanceOf(address(this));
        hub.requestWithdraw(shares);
        vm.warp(block.timestamp + 2 hours + 1);
        // Refresh the secondary asset's feed timestamp so it is NOT stale; we want the liquidity check to fire.
        feed2.set(int256(1_000000), block.timestamp);
        // Try to claim in token2 which has zero balance in hub
        vm.expectRevert(bytes("insufficient liquidity"));
        hub.claimWithdraw(0, address(token2));
    }
}
