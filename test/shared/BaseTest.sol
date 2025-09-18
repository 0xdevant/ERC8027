// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {IPermit2, IAllowanceTransfer} from "@permit2/interfaces/IPermit2.sol";

import "./Constants.sol";
import {TestERC20} from "../TestERC20.sol";
import {DeployPermit2} from "../utils/DeployPermit2.sol";
import {Permit2Utils} from "../utils/Permit2Utils.sol";
import {ISubNFT} from "../../src/ISubNFT.sol";
import {MockSubNFT} from "../../src/mocks/MockSubNFT.sol";

abstract contract BaseTest is Test, Permit2Utils {
    address[] users = new address[](2);
    address serviceProvider = makeAddr("serviceProvider");

    DeployPermit2 deployPermit2 = new DeployPermit2();
    IPermit2 permit2;
    TestERC20 testERC20;
    MockSubNFT subNFT;

    bytes32 PERMIT2_DOMAIN_SEPARATOR;

    function setUp() public virtual {
        uint256[] memory planPrices = new uint256[](1);
        planPrices[0] = DEFAULT_PRICE;

        permit2 = IPermit2(deployPermit2.deployPermit2());
        PERMIT2_DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();
        testERC20 = new TestERC20();

        ISubNFT.SubscriptionConfig memory subscriptionConfig = ISubNFT.SubscriptionConfig({
            paymentToken: address(testERC20),
            serviceProvider: serviceProvider,
            intervalInSec: DEFAULT_INTERVAL,
            planPrices: planPrices
        });
        subNFT = new MockSubNFT("MockSubNFT", "MSNFT", subscriptionConfig, address(permit2));

        setUpUsers();
        // set the timestamp to 0
        vm.warp(0);
    }

    function setUpUsers() public {
        // for user1 and user2
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = vm.addr(USER1_PRIVATE_KEY + i);
            vm.label(users[i], string(abi.encodePacked("User", vm.toString(i))));
            vm.deal(users[i], DEFAULT_BALANCE);

            testERC20.mint(users[i], DEFAULT_BALANCE);

            vm.prank(users[i]);
            testERC20.approve(address(permit2), type(uint256).max);
        }
        subNFT.mint(users[0], TOKEN_ID);
    }
}
