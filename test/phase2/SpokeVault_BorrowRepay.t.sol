// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _mint(msg.sender, 1e24);
    }
}

contract SpokeVaultTest is Test {
    MockToken token;
    SpokeVault vault;

    function setUp() public {
        token = new MockToken("T", "T", 6);
        vault = new SpokeVault();
        vault.initialize(address(token), "svT", "svT", address(this));
    }

    function testBorrowRepay() public {
        // transfer some liquidity to vault
        token.transfer(address(vault), 1_000_000e6);
        vault.setBorrowCap(500_000e6);
        // grant borrower to this test
        vault.grantRole(keccak256("BORROWER_ROLE"), address(this));
        uint256 before = token.balanceOf(address(this));
        vault.borrow(100_000e6, address(this));
        assertEq(token.balanceOf(address(this)), before + 100_000e6);
        // approve vault to pull repayment
        token.approve(address(vault), 100_000e6);
        vault.repay(100_000e6);
        // debt should be zero
        assertEq(vault.utilizationBps(), 0);
    }
}
