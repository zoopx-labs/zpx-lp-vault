// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SharesAggregator} from "../../src/usdzy/SharesAggregator.sol";

contract SharesAggregatorTest is Test {
    SharesAggregator sa;

    function setUp() public {
        sa = new SharesAggregator();
        sa.initialize(address(this));
        sa.setAdapter(address(this));
    }

    function testReportMintBurn() public {
        sa.reportMint(1, 100);
        assertEq(sa.totalGlobalShares(), 100);
        assertEq(sa.perChainShares(1), 100);

        sa.reportBurn(1, 40);
        assertEq(sa.totalGlobalShares(), 60);
        assertEq(sa.perChainShares(1), 60);
    }
}
