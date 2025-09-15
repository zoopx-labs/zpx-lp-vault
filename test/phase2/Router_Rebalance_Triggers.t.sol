// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "../../src/router/Router.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {MockAdapter} from "../../src/messaging/MockAdapter.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("T", "T") {
        _mint(msg.sender, 1e24);
    }
}

contract RouterTest is Test {
    MockToken token;
    SpokeVault vault;
    Router router;
    MockAdapter adapter;

    function setUp() public {
        token = new MockToken();
        vault = new SpokeVault();
        vault.initialize(address(token), "svT", "svT", address(this));
        adapter = new MockAdapter();
        router = new Router();
        router.initialize(address(vault), address(adapter), address(this), address(this));
    }

    function testPokeAndRebalanceTrigger() public {
        SafeERC20.safeTransfer(IERC20(address(token)), address(vault), 1_000_000e18);
        // populate 7 days
        for (uint256 i = 0; i < 7; i++) {
            vm.warp(block.timestamp + 1 days);
            router.pokeTvlSnapshot();
        }
        // now drop TVL and ensure needsRebalance
        SafeERC20.safeTransfer(IERC20(address(token)), address(vault), 0); // no-op
        // simulate low TVL by reducing vault balance
        // cannot directly reduce token balance; but we can simulate by borrowing to remove liquidity
        vault.grantRole(keccak256("BORROWER_ROLE"), address(this));
        vault.setBorrowCap(type(uint256).max);
        vault.borrow(900_000e18, address(0xBEEF));
        assertTrue(router.needsRebalance());
    }
}
