// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PpsBeacon} from "../../src/pps/PpsBeacon.sol";
import {PpsMirror} from "../../src/pps/PpsMirror.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PpsTest is Test {
    PpsBeacon beacon;
    PpsMirror mirror;

    function setUp() public {
        PpsBeacon bImpl = new PpsBeacon();
        address bProxy = ProxyUtils.deployProxy(address(bImpl), abi.encodeCall(PpsBeacon.initialize, (address(this))));
        beacon = PpsBeacon(bProxy);
        // admin already has POSTER_ROLE per initialize()
        PpsMirror mImpl = new PpsMirror();
        address mProxy =
            ProxyUtils.deployProxy(address(mImpl), abi.encodeCall(PpsMirror.initialize, (address(this), 900)));
        mirror = PpsMirror(mProxy);
        // grant poster to test for mirror post
        mirror.grantRole(mirror.POSTER_ROLE(), address(this));
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
