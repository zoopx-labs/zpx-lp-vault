// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZPXArb} from "src/zpx/ZPXArb.sol";
import {MintGate_Arb} from "src/zpx/MintGate_Arb.sol";
import {ZPXRewarder} from "src/zpx/ZPXRewarder.sol";
import {USDzy} from "src/USDzy.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

contract ZPXRewarderTest is Test {
    ZPXArb zpx;
    MintGate_Arb gate;
    ZPXRewarder rewarder;
    USDzy usdzy;
    MockERC20 staker;

    function setUp() public {
        usdzy = new USDzy();
        usdzy.initialize("USDzy", "USZY", address(this));
        // allow this test contract to mint USDzy for staking
        usdzy.grantRole(usdzy.MINTER_ROLE(), address(this));

        zpx = new ZPXArb();
        zpx.initialize("ZPX", "ZPX", address(this));

        gate = new MintGate_Arb(address(zpx));
        // grant gate minter role on zpx
        zpx.grantRole(zpx.MINTER_ROLE(), address(gate));

        rewarder = new ZPXRewarder(address(usdzy), address(zpx), address(this));
        // grant TOPUP_ROLE to gate
        rewarder.grantRole(rewarder.TOPUP_ROLE(), address(gate));

        // prepare a staker USDzy mock
        staker = new MockERC20("USDzyMock", "UDM");
        // mint USDzy tokens to staker and also make usdzy contract mintable for tests
        // For simplicity use USDzy itself as stakeToken in rewarder tests; we will mint USDzy to user directly
    }

    function testTopUpAndClaim() public {
        // gate mints to rewarder and notifies topup (gate is TOPUP_ROLE)
        gate.setEndpoint(1, address(0x1234));
        // mint 100 ZPX to rewarder
        gate.consumeAndMint(1, address(0x1234), 1, address(rewarder), 100e18, bytes32("REWARD_TOPUP"));
        // notify for 100 seconds as gate (prank)
        vm.prank(address(gate));
        rewarder.notifyTopUp(100e18, 100);

        // user stakes USDzy after top-up
        usdzy.mint(address(this), 1e6);
        usdzy.approve(address(rewarder), type(uint256).max);
        rewarder.deposit(1e6);

        // warp 50s, claim partial
        vm.warp(block.timestamp + 50);
        // calculate expected: rate = 100e18/100 = 1e18 per sec; elapsed=50
        uint256 rate = 100e18 / 100;
        uint256 expectedReward = (50 * rate) * 1e6 / 1e6; // simplified since totalStaked equals 1e6
        rewarder.claim();
        uint256 bal = zpx.balanceOf(address(this));
        assertEq(bal, expectedReward);

        // top-up mid-flight: mint another 100 and extend
        gate.consumeAndMint(1, address(0x1234), 2, address(rewarder), 100e18, bytes32("REWARD_TOPUP"));
        vm.prank(address(gate));
        rewarder.notifyTopUp(100e18, 100);

        // warp to end and claim remaining
        vm.warp(block.timestamp + 200);
        rewarder.claim();
        uint256 finalBal = zpx.balanceOf(address(this));
        assertGt(finalBal, bal);
    }
}
