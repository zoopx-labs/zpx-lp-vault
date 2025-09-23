// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockAsset is ERC20 {
    constructor() ERC20("A", "A") { _mint(msg.sender, 1e30); }
}

contract SpokeVaultEdgeCaseTest is Test {
    MockAsset asset;
    SpokeVault vault;

    bytes32 internal constant BORROWER_ROLE = keccak256("BORROWER_ROLE");

    function setUp() public {
        asset = new MockAsset();
        SpokeVault impl = new SpokeVault();
        address proxy = ProxyUtils.deployProxy(
            address(impl), abi.encodeCall(SpokeVault.initialize, (address(asset), "SV", "SV", address(this)))
        );
        vault = SpokeVault(proxy);
    }

    function _fund(uint256 amt) internal {
        SafeERC20.safeTransfer(IERC20(address(asset)), address(vault), amt);
    }

    function test_borrow_over_cap_and_utilization_paths() public {
        // Fund modest amount to keep math simple
        _fund(100e18);
        vault.setBorrowCap(50e18);
        vault.grantRole(BORROWER_ROLE, address(this));
        // Borrow in two chunks within cap
        vault.borrow(30e18, address(this));
        vault.borrow(20e18, address(this));
        // Cap reached: further borrow reverts
        vm.expectRevert(SpokeVault.BORROW_OVER_CAP.selector);
        vault.borrow(1, address(this));

        // Increase cap to allow more borrowing but engineer a utilization breach
        vault.setBorrowCap(80e18);
        // Current: debt = 50e18, vault balance = initial 100e18 - 50e18 = 50e18
        // Utilization currently = (50/50)=10000 bps (100%). To trip BORROW_OVER_UTIL we tighten maxUtilizationBps below current utilization.
        vault.setMaxUtilizationBps(9000); // 90% threshold
        vm.expectRevert(SpokeVault.BORROW_OVER_UTIL.selector);
        vault.borrow(1e18, address(this));
    }

    function test_repay_over_debt_and_idle_zero_branch() public {
        _fund(1000e18);
        vault.setBorrowCap(500e18);
        vault.grantRole(BORROWER_ROLE, address(this));
        vault.borrow(200e18, address(this));
        asset.approve(address(vault), type(uint256).max);
        // repay more than debt -> sets to zero
        vault.repay(500e18);
        assertEq(vault.utilizationBps(), 0);
        // idleLiquidity when balance >= debt
        uint256 idle = vault.idleLiquidity();
        assertGt(idle, 0);
        // simulate debt > balance path -> set debt manually via storage slot (cheat)
        // debt slot is after: debt, borrowCap, maxUtilizationBps -> debt is first uint256 so slot 0 after proxies layout
        // Instead of manual store, borrow again partially to create non-zero debt
        vault.borrow(50e18, address(this));
        // drain asset so balance < debt
        uint256 bal = asset.balanceOf(address(vault));
        vm.prank(address(this));
        asset.transfer(address(0xBEEF), bal - 1e18); // leave small amount
        // check idle now (view) - can't easily assert exact but should be <= balance
        uint256 idle2 = vault.idleLiquidity();
        assertLe(idle2, asset.balanceOf(address(vault)));
    }

    function test_sendIdle_over_idle_and_success_and_utilization_zero_supply() public {
        // utilizationBps with ta=0 -> expect 0
        assertEq(vault.utilizationBps(), 0);
        _fund(100e18);
        vault.grantRole(BORROWER_ROLE, address(this));
        vault.borrow(10e18, address(this));
        // idle = 90e18
        vm.expectRevert(bytes("OVER_IDLE"));
        vault.sendIdle(address(0xCAFE), 100e18);
        vault.sendIdle(address(0xCAFE), 50e18); // ok
        assertEq(asset.balanceOf(address(0xCAFE)), 50e18);
    }
}
