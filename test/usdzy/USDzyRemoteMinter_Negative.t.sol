// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {USDzyRemoteMinter} from "../../src/usdzy/USDzyRemoteMinter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {USDzy} from "../../src/USDzy.sol";

contract USDzyRemoteMinterNegativeTest is Test {
    USDzy usdzy;
    USDzyRemoteMinter minter;
    address admin = address(0xABCD);

    function setUp() public {
        usdzy = new USDzy();
        usdzy.initialize("USDzy", "USZY", address(this));

        USDzyRemoteMinter impl = new USDzyRemoteMinter();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(USDzyRemoteMinter.initialize, (address(usdzy), admin)));
        minter = USDzyRemoteMinter(address(proxy));

        // no GATEWAY_ROLE granted to test caller
    }

    function testMintFromGatewayRevertsForUnauthorized() public {
        vm.expectRevert();
        minter.mintFromGateway(address(0x1), 100);
    }
}
