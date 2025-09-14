// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockToken is IERC20 {
    string public name = "Mock";
    string public symbol = "M";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function approve(address, uint256) external returns (bool) {
        return true;
    }

    function setBalance(address who, uint256 v) external {
        balanceOf[who] = v;
    }
}

contract SpokeVaultIdleTest is Test {
    SpokeVault sv;
    MockToken t;

    function setUp() public {
        t = new MockToken();
        sv = new SpokeVault();
        sv.initialize(address(t), "Spoke", "SPK", address(this));
        // fund vault
        t.setBalance(address(sv), 1000);
    }

    function testSendIdle() public {
        // idle = balance (1000) - debt (0)
        sv.sendIdle(address(0xBEEF), 500);
        // check that event emitted by reading balance
        assertEq(t.balanceOf(address(0xBEEF)), 500);
    }
}
