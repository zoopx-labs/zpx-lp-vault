// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZPXArb} from "src/zpx/ZPXArb.sol";
import {MintGate_Arb} from "src/zpx/MintGate_Arb.sol";

contract MintGateTest is Test {
    ZPXArb zpx;
    MintGate_Arb gate;

    function setUp() public {
        zpx = new ZPXArb();
        zpx.initialize("ZPX", "ZPX", address(this));
        gate = new MintGate_Arb(address(zpx));
        zpx.grantRole(zpx.MINTER_ROLE(), address(gate));
    }

    function testReplayAndEndpoint() public {
        gate.setEndpoint(100, address(0xABC));
        // correct consume
        gate.consumeAndMint(100, address(0xABC), 1, address(this), 10e18, bytes32("REWARD_TOPUP"));

        // replay must revert
        vm.expectRevert(bytes("replay"));
        gate.consumeAndMint(100, address(0xABC), 1, address(this), 10e18, bytes32("REWARD_TOPUP"));

        // wrong endpoint must revert
        vm.expectRevert();
        gate.consumeAndMint(999, address(0xDEF), 2, address(this), 1e18, bytes32("REWARD_TOPUP"));
    }
}
