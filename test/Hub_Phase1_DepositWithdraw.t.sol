// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Hub} from "src/Hub.sol";
import {USDzy} from "src/USDzy.sol";
import {ProxyUtils} from "./utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockDIAFeed} from "src/mocks/MockDIAFeed.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HubPhase1Test is Test {
    USDzy usdzy;
    Hub hub;
    MockERC20 usdc; // 6 decimals
    MockERC20 dai; // 18 decimals
    MockDIAFeed feedUsdc;
    MockDIAFeed feedDai;

    function setUp() public {
        // Deploy USDzy via proxy
        USDzy usdzyImpl = new USDzy();
        address usdzyProxy = ProxyUtils.deployProxy(
            address(usdzyImpl), abi.encodeCall(USDzy.initialize, ("USDzy", "USZY", address(this)))
        );
        usdzy = USDzy(usdzyProxy);

        Hub impl = new Hub();
        address proxy =
            ProxyUtils.deployProxy(address(impl), abi.encodeCall(Hub.initialize, (address(usdzy), address(this))));
        hub = Hub(proxy);

        // grant roles
        usdzy.grantRole(usdzy.MINTER_ROLE(), address(hub));
        usdzy.grantRole(usdzy.BURNER_ROLE(), address(hub));

        usdc = new MockERC20("USDC", "USDC");
        dai = new MockERC20("DAI", "DAI");

        // set decimals: MockERC20 defaults to 18; override by deploying a 6-dec mock as needed
        // For test simplicity, we'll treat usdc as 6-dec by using amounts scaled accordingly.

        // price feeds: priceDecimals = 6 (we'll set feed to return price scaled to 1e6)
        feedUsdc = new MockDIAFeed(int256(1_000000), block.timestamp);
        feedDai = new MockDIAFeed(int256(1_000000), block.timestamp);

        // configure assets
        hub.setAssetConfig(address(usdc), address(feedUsdc), 6, 6, 0, true);
        hub.setAssetConfig(address(dai), address(feedDai), 18, 6, 0, true);
    }

    function testDepositAndWithdrawFlow() public {
        // mint tokens to user
        usdc.mint(address(this), 1_000_000); // 1 USDC as 6-dec
        dai.mint(address(this), 1e18);

        // approve
        IERC20(address(usdc)).approve(address(hub), type(uint256).max);
        IERC20(address(dai)).approve(address(hub), type(uint256).max);

        // deposit 1 USDC
        hub.deposit(address(usdc), 1_000_000);
        uint256 supply = IERC20(address(usdzy)).totalSupply();
        assertTrue(supply > 0, "supply>0");

        // request withdraw
        uint256 shares = usdzy.balanceOf(address(this));
        hub.requestWithdraw(shares);

        // fast forward
        vm.warp(block.timestamp + 2 hours + 1);

        // ensure hub has liquidity: deposit 1 DAI to serve payout
        // refresh DAI price feed so transfer doesn't revert due to staleness after warp
        feedDai.set(int256(1_000000), block.timestamp);
        // send DAI to hub as liquidity without calling hub.deposit (would mint shares to sender)
        SafeERC20.safeTransfer(IERC20(address(dai)), address(hub), 1e18);

        // claim withdraw into DAI
        hub.claimWithdraw(0, address(dai));

        // check that claimed: usdzy balance is 0
        assertEq(usdzy.balanceOf(address(this)), 0);
    }
}
