// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SharesAggregator} from "../../src/usdzy/SharesAggregator.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SharesAggregatorTest is Test {
    SharesAggregator sa;

    function setUp() public {
        SharesAggregator impl = new SharesAggregator();
        address proxy =
            ProxyUtils.deployProxy(address(impl), abi.encodeCall(SharesAggregator.initialize, (address(this))));
        sa = SharesAggregator(proxy);
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
