// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ZPXArb} from "../../src/zpx/ZPXArb.sol";

contract ZPXArbBurnTest is Test {
    address deployer = address(0xBEEF);
    address admin = address(0xCAFE);
    address minter = address(0x1);
    address alice = address(0xA11CE);
    uint256 bobKey = 0xB0B;
    address bob;

    function setUp() public {
        vm.deal(deployer, 1 ether);
        vm.deal(admin, 1 ether);
        vm.deal(minter, 1 ether);
        vm.deal(alice, 1 ether);
        bob = vm.addr(bobKey);
        vm.deal(bob, 1 ether);
    }

    function test_burn_and_burnFromWithPermit() public {
        vm.prank(deployer);
        ZPXArb impl = new ZPXArb();
        bytes memory init = abi.encodeWithSelector(ZPXArb.initialize.selector, "ZPX", "ZPX", admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        ZPXArb z = ZPXArb(address(proxy));

        // grant MINTER_ROLE to minter
        vm.startPrank(admin);
        bytes32 minterRole = z.MINTER_ROLE();
        z.grantRole(minterRole, minter);
        vm.stopPrank();

        // mint to alice
        vm.prank(minter);
        z.mint(alice, 1000 ether);
        assertEq(z.balanceOf(alice), 1000 ether);

        // alice burns 200
        vm.prank(alice);
        z.burn(200 ether);
        assertEq(z.balanceOf(alice), 800 ether);

        // mint to bob for permit test
        vm.prank(minter);
        z.mint(bob, 500 ether);
        assertEq(z.balanceOf(bob), 500 ether);

        // bob signs permit for this contract to burn 300 of his tokens
        uint256 nonce = z.nonces(bob);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 domain = z.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, bob, address(this), 300 ether, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, digest);

        // call burnFromWithPermit as this contract
        z.burnFromWithPermit(bob, 300 ether, deadline, v, r, s);
        assertEq(z.balanceOf(bob), 200 ether);
    }
}
