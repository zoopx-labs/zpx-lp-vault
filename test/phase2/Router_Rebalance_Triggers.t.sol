// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "../../src/router/Router.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {MockAdapter} from "../../src/messaging/MockAdapter.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", address(this)))
        );
        vault = SpokeVault(vProxy);
        adapter = new MockAdapter();
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl),
            abi.encodeCall(Router.initialize, (address(vault), address(adapter), address(this), address(this)))
        );
        router = Router(rProxy);
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
