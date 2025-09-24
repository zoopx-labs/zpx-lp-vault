// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ZPXRewarder} from "src/zpx/ZPXRewarder.sol";
import {USDzy} from "src/USDzy.sol";
import {ZPXArb} from "src/zpx/ZPXArb.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ZPXRewarderExpandedTest is Test {
    USDzy usdzy;
    ZPXArb zpx;
    ZPXRewarder rewarder;
    address admin = address(0xA11CE);
    address topup = address(0xBEEF);
    address user = address(0xCAFE);

    function setUp() public {
        // Deploy USDzy proxy
        USDzy implU = new USDzy();
        address pU = ProxyUtils.deployProxy(address(implU), abi.encodeCall(USDzy.initialize, ("USDzy", "USZY", admin)));
        usdzy = USDzy(pU);
        // allow test to mint to users via MINTER_ROLE
        bytes32 minterRole = usdzy.MINTER_ROLE(); // cache before prank (avoids an extra call inside prank window)
        vm.startPrank(admin);
        usdzy.grantRole(minterRole, address(this));

        // Deploy ZPX implementation (non-upgradeable in tests) & initialize
        zpx = new ZPXArb();
        zpx.initialize("ZPX", "ZPX", admin);
        // grant topup address minter capability to simulate gate funding
        zpx.grantRole(zpx.MINTER_ROLE(), topup);

        rewarder = new ZPXRewarder(address(usdzy), address(zpx), admin);
        rewarder.grantRole(rewarder.TOPUP_ROLE(), topup);

        vm.stopPrank();

        // Seed user with stake token (USDzy) and approve
        usdzy.mint(user, 10_000e6);
        vm.prank(user);
        usdzy.approve(address(rewarder), type(uint256).max);
    }

    function _fund(uint256 amount, uint64 dur, address caller) internal {
        // caller already has MINTER_ROLE
        vm.prank(caller);
        zpx.mint(address(rewarder), amount);
        vm.prank(caller);
        rewarder.notifyTopUp(amount, dur);
    }

    function test_deposit_claim_withdraw_fullLifecycle() public {
        _fund(100e18, 100, topup); // 1e18 per sec
        // user deposits
        vm.prank(user);
        rewarder.deposit(1_000e6);
        vm.warp(block.timestamp + 25);
        // claim partial
        vm.prank(user);
        rewarder.claim();
        uint256 balAfterClaim = zpx.balanceOf(user);
        assertGt(balAfterClaim, 0, "partial reward");
        // warp further and withdraw (auto-claims remaining)
        vm.warp(block.timestamp + 75);
        vm.prank(user);
        rewarder.withdraw(500e6);
        assertGt(zpx.balanceOf(user), balAfterClaim, "more rewards after withdraw");
    }

    function test_emergencyWithdraw_noRewardsClaimed() public {
        _fund(50e18, 50, topup);
        vm.prank(user);
        rewarder.deposit(2_000e6);
        vm.prank(user);
        rewarder.emergencyWithdraw();
        assertEq(zpx.balanceOf(user), 0, "no reward claim on emergency");
    }

    function test_notifyTopUp_mergeLeftover() public {
        _fund(100e18, 100, topup); // start stream
        vm.prank(user);
        rewarder.deposit(1_000e6);
        vm.warp(block.timestamp + 40);
        // second top-up mid-flight extends schedule
        _fund(50e18, 50, topup);
        vm.warp(block.timestamp + 60); // move past original end but within extended
        vm.prank(user);
        rewarder.claim();
        assertGt(zpx.balanceOf(user), 0, "rewards after merged topup");
    }

    function test_claim_noRewardReverts() public {
        vm.prank(user);
        rewarder.deposit(500e6);
        // Immediately claim before any funding -> expect revert (no reward)
        vm.prank(user);
        vm.expectRevert();
        rewarder.claim();
    }
}
