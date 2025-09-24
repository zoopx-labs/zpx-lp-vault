// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Router} from "src/router/Router.sol";
import {SpokeVault} from "src/spoke/SpokeVault.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {ProxyUtils} from "test/utils/ProxyUtils.sol";

// Focus: cover branch where protocolFee + relayerFee >= amount resulting in net=0 in fill()
contract RouterFillZeroNetTest is Test {
    Router router;
    SpokeVault vault;
    MockERC20 token;
    address admin = address(0xA11CE);
    address relayer = address(0xBEEF);
    address user = address(0xCAFE);
    address feeCollector = address(0xD00D);

    function setUp() public {
        token = new MockERC20("Tkn", "TKN");
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", admin))
        );
        vault = SpokeVault(vProxy);
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl), abi.encodeCall(Router.initialize, (address(vault), address(0x1), admin, feeCollector))
        );
        router = Router(rProxy);

        // fund vault to allow borrows
        token.mint(address(vault), 1_000_000e6);

        vm.startPrank(admin);
        router.grantRole(router.RELAYER_ROLE(), relayer);
        vault.grantRole(vault.BORROWER_ROLE(), address(router));
        router.setFeeCollector(feeCollector);
        router.setProtocolFeeBps(5); // 5 bps protocol fee
        router.setRelayerFeeBps(10000); // 100% relayer fee so protocolFee+relayerFee > amount triggers net=0 branch
        router.setFeeSplit(2500, 7500); // ensure split set (though protocolFee small)
        vm.stopPrank();
    }

    function testFillZeroNetBranch() public {
        uint256 amount = 1_000_000; // token has 6 decimals semantics but raw arithmetic fine
        uint256 userBefore = token.balanceOf(user);
        uint256 relayerBefore = token.balanceOf(relayer);
        uint256 vaultBefore = token.balanceOf(address(vault));

        // call fill as relayer; expect net=0 so user gets nothing (no borrow for net portion)
        vm.prank(relayer);
        router.fill(user, amount);

        // protocolFee = amount * 5 / 10000 = 0.0005 * amount = 500
        uint256 protocolFee = (amount * 5) / 10000; // 500
        uint256 relayerFee = (amount * 10000) / 10000; // 100% = amount
        // protocolFee + relayerFee > amount => net forced to 0

        // relayer receives its fee via borrow
        assertEq(token.balanceOf(relayer), relayerBefore + relayerFee);
        // user receives nothing (net=0)
        assertEq(token.balanceOf(user), userBefore);
        // vault balance decreases by amounts actually borrowed: relayerFee (1,000,000) + protocolFee to feeCollector (500)
        // LP share (protocolFee * lpShareBps/10000) stays in vault = 500 * 7500 / 10000 = 375
        // Treasury share borrowed = 500 * 2500 / 10000 = 125; but we didn't explicitly compute earlier. Borrow to feeCollector is full toTreasury (125)
        // Protocol to LPs (375) remains in vault. Effective vault delta = relayerFee + toTreasury + net(0)
        uint256 toTreasury = (protocolFee * 2500) / 10000; // 125
        uint256 expectedVault = vaultBefore - relayerFee - toTreasury; // -1_000_000 - 125
        assertEq(token.balanceOf(address(vault)), expectedVault);
    }
}
