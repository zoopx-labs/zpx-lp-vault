// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {LocalDepositGateway} from "../../src/gateway/LocalDepositGateway.sol";
import {ProxyUtils} from "../utils/ProxyUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockFeed {
    int256 public answer;
    uint256 public ts;

    constructor(int256 a) {
        answer = a;
        ts = block.timestamp;
    }

    function latestAnswer() external view returns (int256) {
        return answer;
    }

    function latestTimestamp() external view returns (uint256) {
        return ts;
    }
}

contract MockMinter {
    event Minted(address to, uint256 shares);

    function mintFromGateway(address to, uint256 shares) external {
        emit Minted(to, shares);
    }
}

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function approve(address, uint256) external returns (bool) {
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    // helper for tests
    function setBalance(address who, uint256 v) external {
        balanceOf[who] = v;
    }
}

contract MockSpoke {
    address public token;

    constructor(address t) {
        token = t;
    }
}

contract MockPps {
    uint256 public pps;
    uint64 public ts;

    constructor(uint256 p) {
        pps = p;
        ts = uint64(block.timestamp);
    }

    function latestPps6() external view returns (uint256, uint64) {
        return (pps, ts);
    }
}

contract GatewayDepositTest is Test {
    LocalDepositGateway gw;
    MockFeed f;
    MockMinter m;
    MockToken t;
    MockSpoke s;

    function setUp() public {
        t = new MockToken();
        s = new MockSpoke(address(t));
        m = new MockMinter();
        f = new MockFeed(1e6); // price 1.0
        LocalDepositGateway impl = new LocalDepositGateway();
        MockPps mp = new MockPps(1e6);
        address proxy = ProxyUtils.deployProxy(
            address(impl),
            abi.encodeCall(LocalDepositGateway.initialize, (address(m), address(mp), address(s), address(this), 900))
        );
        gw = LocalDepositGateway(proxy);
        gw.setAssetConfig(address(t), address(f), 6, 6, 100, true);
        t.setBalance(address(this), 1000);
    }

    function testDeposit() public {
        t.setBalance(address(this), 1000);
        // deposit 100 tokens -> usd6 = 100 * 1 = 100, haircut 1% -> 99 usd6
        gw.deposit(address(t), 100);
        // check token forwarded to spoke
        assertEq(t.balanceOf(address(s)), 100);
    }
}
