// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {LocalDepositGateway} from "../../src/gateway/LocalDepositGateway.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockDIAFeed} from "../../src/mocks/MockDIAFeed.sol";
import {PpsBeacon} from "../../src/pps/PpsBeacon.sol";

contract MockMinter {
    event Minted(address to, uint256 shares);
    function mintFromGateway(address to, uint256 shares) external {
        emit Minted(to, shares);
    }
}

contract LocalDepositGatewayEdges is Test {
    LocalDepositGateway gw;
    MockERC20 token;
    MockDIAFeed feed;
    PpsBeacon pps;

    function setUp() public {
        token = new MockERC20("Tkn", "TKN");
        pps = new PpsBeacon();
        pps.initialize(address(this));
    pps.post(1e6, uint64(block.timestamp));
        feed = new MockDIAFeed(int256(1_000000), block.timestamp);

    MockMinter mock = new MockMinter();
    gw = new LocalDepositGateway();
    gw.initialize(address(mock), address(pps), address(0x1), address(this), 1000);
    // MockERC20 has 18 decimals; reflect that in the gateway config
    gw.setAssetConfig(address(token), address(feed), 18, 6, 100, true);
    }

    function testPpsStaleReverts() public {
    // set pps timestamp to zero (stale) to trigger PPS_STALE without arithmetic underflow
    pps.post(1e6, uint64(0));
    token.mint(address(this), 1e18);
    token.approve(address(gw), type(uint256).max);
    vm.expectRevert();
    gw.deposit(address(token), 1e18);
    }

    function testHaircutRoundsToZeroForTinyDeposits() public {
        // set pps fresh
        pps.post(1e6, uint64(block.timestamp));
        // tiny deposit that after haircut yields zero shares
    token.mint(address(this), 1e12); // tiny amount with 18-decimals
    token.approve(address(gw), 1e12);
    // this may revert due to ZERO_SHARES after haircut; accept revert
    vm.expectRevert();
    gw.deposit(address(token), 1e12);
    }
}
