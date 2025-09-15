// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PolicyBeacon, IPolicySource} from "../../src/policy/PolicyBeacon.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PolicyBeaconTest is Test {
    PolicyBeacon beacon;

    function setUp() public {
        PolicyBeacon impl = new PolicyBeacon();
        address proxy = ProxyUtils.deployProxy(address(impl), abi.encodeCall(PolicyBeacon.initialize, (address(this))));
        beacon = PolicyBeacon(proxy);
        // grant POSTER_ROLE to this test account to call post
        beacon.grantRole(beacon.POSTER_ROLE(), address(this));
    }

    function testPostAndLatest() public {
        beacon.post(
            1,
            address(0),
            address(0),
            1000,
            2000,
            5000,
            IPolicySource.State.Ok,
            uint64(block.timestamp),
            bytes32("ref"),
            true
        );
        address spoke = address(0xBEEF);
        address router = address(0xCAFE);
        beacon.post(
            1, spoke, router, 1000, 2000, 5000, IPolicySource.State.Ok, uint64(block.timestamp), bytes32("ref"), true
        );
        (uint256 tvl, uint256 ma7, uint16 coverage, IPolicySource.State st, uint64 asOf) = beacon.latestOf(spoke);
        assertEq(tvl, 1000);
        assertEq(ma7, 2000);
        assertEq(coverage, 5000);
        assertEq(uint256(st), uint256(IPolicySource.State.Ok));
        assertTrue(asOf > 0);
    }
}
