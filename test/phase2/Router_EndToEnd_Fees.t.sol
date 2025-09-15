// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "../..//src/mocks/MockERC20.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {SpokeVault} from "../../src/spoke/SpokeVault.sol";
import {Router} from "../../src/router/Router.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RouterEndToEndFees is Test {
    MockUSDC token;
    SpokeVault vault;
    Router router;

    // scenario accumulators moved to storage to reduce local stack usage
    uint256 private scenario_totalProtocolFees;
    uint256 private scenario_totalRelayerFees;
    uint256 private scenario_totalToTreasury;
    uint256 private scenario_totalToLPs;

    address admin = address(0xABCD);
    address relayer = address(0xBEEF);
    address user = address(0xCAFE);
    address treasury = address(0xD00D);

    function setUp() public {
        // use a 6-decimal USDC-like mock for stablecoin behavior
        token = new MockUSDC("Mock USDC", "mUSDC");
        SpokeVault vImpl = new SpokeVault();
        address vProxy = ProxyUtils.deployProxy(
            address(vImpl), abi.encodeCall(SpokeVault.initialize, (address(token), "svT", "SVT", admin))
        );
        vault = SpokeVault(vProxy);
        // allow high utilization for the test so repeated borrows succeed
        vm.prank(admin);
        vault.setMaxUtilizationBps(65000);
        Router rImpl = new Router();
        address rProxy = ProxyUtils.deployProxy(
            address(rImpl), abi.encodeCall(Router.initialize, (address(vault), address(0x1), admin, treasury))
        );
        router = Router(rProxy);

        // mint a much larger balance into the vault to cover repeated fills
        uint256 amount = 5000 ether; // treat 1 token ~= $1 for the test
        uint256 rounds = 100;
        // create mock liquidity of 1,000,000 USDC (6 decimals)
        token.mint(address(vault), 1_000_000 * 10 ** 6);

        // grant roles
        vm.startPrank(admin);
        router.grantRole(keccak256("RELAYER_ROLE"), relayer);
        vault.grantRole(vault.BORROWER_ROLE(), address(router));
        vm.stopPrank();

        // set fees
        vm.prank(admin);
        router.setFeeCollector(treasury);
        vm.prank(admin);
        router.setProtocolFeeBps(5); // 5 bps
        vm.prank(admin);
        router.setRelayerFeeBps(20); // 20 bps
        vm.prank(admin);
        router.setFeeSplit(2500, 7500); // 25% treasury / 75% LPs
    }

    // helper to perform end-of-day rebalance logic to keep the vault at `target`
    function _rebalanceAfterDay(MockUSDC t, SpokeVault v, uint256 target, address adminAddr) internal {
        uint256 balAfter = t.balanceOf(address(v));
        if (balAfter < target) {
            // top up shortfall so we can perform sendIdle calculations consistently next day
            t.mint(address(v), target - balAfter);
            balAfter = target;
        }

        uint256 debt = v.debt();
        // if vault has more than target, send idle back to admin to leave exactly `target` in vault
        if (balAfter > target) {
            uint256 toSend = balAfter - target;
            vm.prank(adminAddr);
            v.sendIdle(adminAddr, toSend);
            return;
        }

        // fallback sanity: if vault has idle above target, send it
        if (balAfter > debt && balAfter > target) {
            uint256 idle = balAfter > debt ? balAfter - debt : 0;
            if (idle > 0) {
                uint256 toSend = idle > (balAfter - target) ? (balAfter - target) : idle;
                vm.prank(adminAddr);
                v.sendIdle(adminAddr, toSend);
            }
        }
    }

    function test100BridgesOf5kAndReport() public {
        // amount and rounds for the simulation (USDC with 6 decimals)
        uint256 amount = 5000 * 10 ** 6; // 5,000 USDC
        uint256 rounds = 100;

        uint256 totalProtocolFees;
        uint256 totalRelayerFees;
        uint256 totalToTreasury;
        uint256 totalToLPs;
        uint256 totalNet;

        uint256 start = block.timestamp;

        for (uint256 i = 0; i < rounds; i++) {
            // advance one day between fills to simulate activity over time
            vm.warp(block.timestamp + 1 days);

            vm.prank(relayer);
            router.fill(user, amount);

            uint256 protocolFee = (amount * uint256(router.protocolFeeBps())) / 10000;
            uint256 relayerFee = (amount * uint256(router.relayerFeeBps())) / 10000;
            uint256 toTreasury = (protocolFee * uint256(router.protocolShareBps())) / 10000;
            uint256 toLPs = protocolFee - toTreasury;
            uint256 net = amount - protocolFee - relayerFee;

            totalProtocolFees += protocolFee;
            totalRelayerFees += relayerFee;
            totalToTreasury += toTreasury;
            totalToLPs += toLPs;
            totalNet += net;
        }

        uint256 daysPassed = (block.timestamp - start) / 1 days;
        if (daysPassed == 0) daysPassed = 1;

        uint256 totalBridged = amount * rounds;

        // Print summary (human-readable USDC values)
        emit log_named_uint("rounds", rounds);
        emit log_named_uint("amount_per_round (USDC)", amount / 10 ** 6);
        emit log_named_uint("total_bridged (USDC)", totalBridged / 10 ** 6);
        emit log_named_uint("total_protocol_fees (USDC)", totalProtocolFees / 10 ** 6);
        emit log_named_uint("total_relayer_fees (USDC)", totalRelayerFees / 10 ** 6);
        emit log_named_uint("total_to_treasury (USDC)", totalToTreasury / 10 ** 6);
        emit log_named_uint("total_to_LPs (USDC)", totalToLPs / 10 ** 6);
        emit log_named_uint("total_net_to_users (USDC)", totalNet / 10 ** 6);
        emit log_named_uint("days_passed", daysPassed);

        // APR (simple annualization of LP share over period vs total bridged)
        // APR = (totalToLPs / totalBridged) * (365 / daysPassed)
        // Represent APR in basis points (1e4 = 100%) scaled by 1e18 for precision
        uint256 aprRay = 0;
        if (totalBridged > 0) {
            // use ray style 1e18 for fractional math
            aprRay = (totalToLPs * 1e18 / totalBridged) * 365 / daysPassed;
        }

        emit log_named_uint("apr_ray(1e18) for LPs", aprRay);

        // basic asserts: balances match computed totals (using 6-decimal units)
        assertEq(token.balanceOf(treasury), totalToTreasury);
        assertEq(token.balanceOf(user), totalNet);
        assertEq(token.balanceOf(relayer), totalRelayerFees);
        // vault balance should be initial - totalBridged + totalToLPs (LP share retained)
        // initial minted in setUp was 1,000,000 USDC (6 decimals)
        uint256 initial = 1_000_000 * 10 ** 6;
        uint256 expectedVault = initial - totalBridged + totalToLPs;
        assertEq(token.balanceOf(address(vault)), expectedVault);
    }

    function testDaily100TxWithRebalanceScenarios() public {
        uint256[] memory daysList = new uint256[](3);
        daysList[0] = 5;
        daysList[1] = 10;
        daysList[2] = 36;

        for (uint256 s = 0; s < daysList.length; s++) {
            uint256 daysRun = daysList[s];
            _runRebalanceScenario(daysRun);

            // read accumulators from storage and print scenario results in human-readable USDC
            emit log_named_uint("scenario_days", daysRun);
            emit log_named_uint("total_tx_executed", daysRun * 100);
            emit log_named_uint("total_protocol_fees (USDC)", scenario_totalProtocolFees / 10 ** 6);
            emit log_named_uint("total_relayer_fees (USDC)", scenario_totalRelayerFees / 10 ** 6);
            emit log_named_uint("total_to_treasury (USDC)", scenario_totalToTreasury / 10 ** 6);
            emit log_named_uint("total_to_LPs (USDC)", scenario_totalToLPs / 10 ** 6);
        }
    }

    function _runRebalanceScenario(uint256 daysRun) internal returns (uint256, uint256, uint256, uint256) {
        // create fresh instances for each scenario to isolate state
        MockUSDC t = new MockUSDC("Mock USDC", "mUSDC");
        SpokeVault vImpl2 = new SpokeVault();
        address vProxy2 = ProxyUtils.deployProxy(
            address(vImpl2), abi.encodeCall(SpokeVault.initialize, (address(t), "svT", "SVT", admin))
        );
        SpokeVault v = SpokeVault(vProxy2);
        // allow higher utilization for scenario vaults so repeated borrows within a day succeed
        vm.prank(admin);
        v.setMaxUtilizationBps(65000);
        Router rImpl2 = new Router();
        address rProxy2 = ProxyUtils.deployProxy(
            address(rImpl2), abi.encodeCall(Router.initialize, (address(v), address(0x1), admin, treasury))
        );
        Router r = Router(rProxy2);

        // roles
        vm.startPrank(admin);
        r.grantRole(keccak256("RELAYER_ROLE"), relayer);
        v.grantRole(v.BORROWER_ROLE(), address(r));
        vm.stopPrank();

        // set fees
        vm.prank(admin);
        r.setFeeCollector(treasury);
        vm.prank(admin);
        r.setProtocolFeeBps(5);
        vm.prank(admin);
        r.setRelayerFeeBps(20);
        vm.prank(admin);
        r.setFeeSplit(2500, 7500);

        // target vault liquidity after rebalance (1,000,000 USDC)
        uint256 target = 1_000_000 * 10 ** 6;
        uint256 amount = 5000 * 10 ** 6; // 5,000 USDC
        uint256 dailyOutflow = 100 * amount; // total daily outflow
        // We'll rely on per-day pre-funding to `target` at the start of each day

        // reset storage accumulators
        scenario_totalProtocolFees = 0;
        scenario_totalRelayerFees = 0;
        scenario_totalToTreasury = 0;
        scenario_totalToLPs = 0;

        // simulate daysRun days
        for (uint256 day = 0; day < daysRun; day++) {
            _runSingleDayBatch(t, v, r, amount, target);

            // no extra requiredStart top-ups needed; daily pre-funding keeps utilization in check
        }

        return (scenario_totalProtocolFees, scenario_totalRelayerFees, scenario_totalToTreasury, scenario_totalToLPs);
    }

    function _runSingleDayBatch(MockUSDC t, SpokeVault v, Router r, uint256 amount, uint256 target) internal {
        // Ensure vault has `target` liquidity at the start of the day's batch
        uint256 startOfDayBal = t.balanceOf(address(v));
        if (startOfDayBal < target) {
            // top up shortfall so the day's 100 tx can execute without hitting utilization cap
            t.mint(address(v), target - startOfDayBal);
        }

        // 100 tx per day
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(relayer);
            r.fill(user, amount);

            uint256 protoFee = (amount * uint256(r.protocolFeeBps())) / 10000;
            uint256 relFee = (amount * uint256(r.relayerFeeBps())) / 10000;

            // update storage accumulators
            scenario_totalProtocolFees += protoFee;
            scenario_totalRelayerFees += relFee;
            scenario_totalToTreasury += (protoFee * uint256(r.protocolShareBps())) / 10000;
            scenario_totalToLPs += protoFee - ((protoFee * uint256(r.protocolShareBps())) / 10000);

            // small time advance to vary block timestamp
            vm.warp(block.timestamp + 1);
        }

        // repay the day's debt so debt doesn't accumulate across days (simulate external liquidity refill)
        uint256 dayDebt = v.debt();
        if (dayDebt > 0) {
            // mint to admin and approve vault to pull funds
            t.mint(admin, dayDebt);
            vm.prank(admin);
            t.approve(address(v), dayDebt);
            vm.prank(admin);
            v.repay(dayDebt);
        }

        // rebalance to exactly `target` after the day's volume
        _rebalanceAfterDay(t, v, target, admin);

        return;
    }
}
