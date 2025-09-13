// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";

contract SpokeVaultUpgrade is Test {
    function testUpgradeSpokeVaultKeepsState() public {
        SpokeVault impl = new SpokeVault();
        address admin = address(this);
        bytes memory init = abi.encodeCall(SpokeVault.initialize, (address(0x1), "n", "s", admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        SpokeVault vault = SpokeVault(address(proxy));

        // set borrow cap
        vault.setBorrowCap(1_000_000);
        assertEq(vault.maxBorrow(), 1_000_000);

        // upgrade
    SpokeVault impl2 = new SpokeVault();
    bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    vm.store(address(vault), implSlot, bytes32(uint256(uint160(address(impl2)))));

        // state preserved
        assertEq(vault.maxBorrow(), 1_000_000);
    }
}
