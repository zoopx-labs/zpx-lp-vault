// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PpsBeacon} from "../../src/pps/PpsBeacon.sol";
import {PpsMirror} from "../../src/pps/PpsMirror.sol";

contract PpsTest is Test {
    PpsBeacon beacon;
    PpsMirror mirror;

    function setUp() public {
        beacon = new PpsBeacon();
        beacon.initialize(address(this));
        mirror = new PpsMirror();
        mirror.initialize(address(this), 900);
    }

    function testPostAndMirror() public {
        beacon.post(1e6, uint64(block.timestamp));
        (uint256 p, uint64 ts) = beacon.latestPps6();
        assertEq(p, 1e6);

        // mirror posting
        mirror.post(p, ts);
        (uint256 mp, uint64 mts) = mirror.latestPps6();
        assertEq(mp, p);
        assertEq(mts, ts);
    }
}
