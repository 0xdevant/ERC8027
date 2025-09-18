// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPermit2} from "@permit2/interfaces/IPermit2.sol";
import {console} from "forge-std/console.sol";

import "./shared/Constants.sol";
import {TestERC20} from "./TestERC20.sol";
import {BaseTest} from "./shared/BaseTest.sol";
import {ISubNFT} from "../src/ISubNFT.sol";

contract SubNFTTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testRenewSubscription_ERC20Payment() public {
        uint256 user1BalanceBefore = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceBefore = testERC20.balanceOf(serviceProvider);

        vm.startPrank(users[0]);
        testERC20.approve(address(subNFT), type(uint256).max);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.SubscriptionExtended(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS);
        subNFT.renewSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);
        vm.stopPrank();

        uint256 user1BalanceAfter = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceAfter = testERC20.balanceOf(serviceProvider);

        assertEq(subNFT.getSubscriptionDetails(TOKEN_ID).planIdx, DEFAULT_PLAN_IDX);
        assertEq(subNFT.expiresAt(TOKEN_ID), DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS);
        assertEq(user1BalanceAfter, user1BalanceBefore - DEFAULT_PRICE * DEFAULT_NUM_OF_INTERVALS);
        assertEq(serviceProviderBalanceAfter, serviceProviderBalanceBefore + DEFAULT_PRICE * DEFAULT_NUM_OF_INTERVALS);
    }

    function testRenewalSubscription_ExistingSubscription() public {
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.SubscriptionExtended(TOKEN_ID2, DEFAULT_PLAN_IDX, DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS);
        subNFT.mintWithSubscription(users[1], TOKEN_ID2, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);

        // This renewal should fail because the subscription is not renewable
        vm.startPrank(users[1]);
        testERC20.approve(address(subNFT), type(uint256).max);
        vm.expectRevert(ISubNFT.SubscriptionNotRenewable.selector);
        subNFT.renewSubscription(TOKEN_ID2, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);
        vm.stopPrank();

        subNFT.setRenewable(true);

        // This renewal will succeed because the subscription is renewable
        vm.prank(users[1]);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.SubscriptionExtended(TOKEN_ID2, DEFAULT_PLAN_IDX, DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS * 2);
        subNFT.renewSubscription(TOKEN_ID2, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);
    }

    function testRenewSubscription_NativeTokenPayment() public {
        uint256[] memory planPrices = new uint256[](1);
        planPrices[0] = DEFAULT_PRICE;
        subNFT.setSubscriptionConfig(
            ISubNFT.SubscriptionConfig({
                paymentToken: address(0), // native token
                serviceProvider: serviceProvider,
                intervalInSec: DEFAULT_INTERVAL,
                planPrices: planPrices
            })
        );

        uint256 serviceProviderBalanceBefore = address(serviceProvider).balance;

        vm.prank(users[0]);
        subNFT.renewSubscription{value: DEFAULT_PRICE * DEFAULT_NUM_OF_INTERVALS}(
            TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS
        );

        uint256 serviceProviderBalanceAfter = address(serviceProvider).balance;
        assertEq(serviceProviderBalanceAfter, serviceProviderBalanceBefore + DEFAULT_PRICE * DEFAULT_NUM_OF_INTERVALS);
    }

    function testRenewSubscription_RevertWhenInvalidTokenId() public {
        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.InvalidTokenId.selector);
        subNFT.renewSubscription(TOKEN_ID + 10, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);
    }

    function testRenewSubscription_RevertWhenInvalidPlanIdx() public {
        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.InvalidPlanIdx.selector);
        subNFT.renewSubscription(TOKEN_ID, DEFAULT_PLAN_IDX + 1, DEFAULT_NUM_OF_INTERVALS);
    }

    function testRenewSubscription_RevertWhenInvalidNumOfIntervals() public {
        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.InvalidNumOfIntervals.selector);
        subNFT.renewSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, 0);
    }

    function testRenewSubscription_RevertWhenInsufficientPayment() public {
        uint256[] memory planPrices = new uint256[](1);
        planPrices[0] = DEFAULT_PRICE;
        subNFT.setSubscriptionConfig(
            ISubNFT.SubscriptionConfig({
                paymentToken: address(0), // native token
                serviceProvider: serviceProvider,
                intervalInSec: DEFAULT_INTERVAL,
                planPrices: planPrices
            })
        );

        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.InsufficientPayment.selector);
        subNFT.renewSubscription{value: 0.09 ether}(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_INTERVAL);
    }

    // e.g. user1 wants to sub to Netflix with 100 ERC20 / month for 3 months i.e. Approve 300 ERC20 in total and pay 100 ERC20 per month
    function testSignalAutoSubscription() public {
        IPermit2.PermitSingle memory permitSingle = defaultERC20PermitAllowance(
            address(testERC20),
            uint160(DEFAULT_TOTAL_AMOUNT),
            uint48(block.timestamp + DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS),
            uint48(DEFAULT_NONCE),
            address(subNFT)
        );

        ISubNFT.Permit2Data memory permit2Data = ISubNFT.Permit2Data({
            permitSingle: permitSingle,
            signature: getPermitSignature(permitSingle, USER1_PRIVATE_KEY, PERMIT2_DOMAIN_SEPARATOR)
        });

        vm.prank(users[0]);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.AutoSubscriptionSignaled(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);
        subNFT.signalAutoSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS, permit2Data);

        (uint160 amount, uint48 expiration, uint48 nonce) =
            permit2.allowance(users[0], address(testERC20), address(subNFT));
        assertEq(amount, DEFAULT_TOTAL_AMOUNT);
        assertEq(expiration, block.timestamp + DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS);
        assertEq(nonce, DEFAULT_NONCE + 1);
    }

    function testSignalAutoSubscription_RevertWhenPaymentTokenMismatch() public {
        IPermit2.PermitSingle memory permitSingle = defaultERC20PermitAllowance(
            address(new TestERC20()),
            uint160(DEFAULT_TOTAL_AMOUNT),
            uint48(block.timestamp + DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS),
            uint48(DEFAULT_NONCE),
            address(subNFT)
        );

        ISubNFT.Permit2Data memory permit2Data = ISubNFT.Permit2Data({
            permitSingle: permitSingle,
            signature: getPermitSignature(permitSingle, USER1_PRIVATE_KEY, PERMIT2_DOMAIN_SEPARATOR)
        });

        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.PaymentTokenMismatch.selector);
        subNFT.signalAutoSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS, permit2Data);
    }

    function testSignalAutoSubscription_RevertWhenInsufficientPayment() public {
        IPermit2.PermitSingle memory permitSingle = defaultERC20PermitAllowance(
            address(testERC20),
            uint160(DEFAULT_TOTAL_AMOUNT - 1),
            uint48(block.timestamp + DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS),
            uint48(DEFAULT_NONCE),
            address(subNFT)
        );

        ISubNFT.Permit2Data memory permit2Data = ISubNFT.Permit2Data({
            permitSingle: permitSingle,
            signature: getPermitSignature(permitSingle, USER1_PRIVATE_KEY, PERMIT2_DOMAIN_SEPARATOR)
        });

        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.InsufficientPayment.selector);
        subNFT.signalAutoSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS, permit2Data);
    }

    function testSignalAutoSubscription_RevertWhenAllowanceExpireTooEarly() public {
        IPermit2.PermitSingle memory permitSingle = defaultERC20PermitAllowance(
            address(testERC20),
            uint160(DEFAULT_TOTAL_AMOUNT),
            uint48(block.timestamp + DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS - 1),
            uint48(DEFAULT_NONCE),
            address(subNFT)
        );

        ISubNFT.Permit2Data memory permit2Data = ISubNFT.Permit2Data({
            permitSingle: permitSingle,
            signature: getPermitSignature(permitSingle, USER1_PRIVATE_KEY, PERMIT2_DOMAIN_SEPARATOR)
        });

        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.AllowanceExpireTooEarly.selector);
        subNFT.signalAutoSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS, permit2Data);
    }

    function testSignalAutoSubscription_RevertWhenInvalidSpender() public {
        IPermit2.PermitSingle memory permitSingle = defaultERC20PermitAllowance(
            address(testERC20),
            uint160(DEFAULT_TOTAL_AMOUNT),
            uint48(block.timestamp + DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS),
            uint48(DEFAULT_NONCE),
            address(1)
        );

        ISubNFT.Permit2Data memory permit2Data = ISubNFT.Permit2Data({
            permitSingle: permitSingle,
            signature: getPermitSignature(permitSingle, USER1_PRIVATE_KEY, PERMIT2_DOMAIN_SEPARATOR)
        });

        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.InvalidSpender.selector);
        subNFT.signalAutoSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS, permit2Data);
    }

    function testChargeAutoSubscription() public {
        testSignalAutoSubscription();
        vm.warp(1);

        uint256 user1BalanceBefore = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceBefore = testERC20.balanceOf(serviceProvider);

        vm.prank(users[1]);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.AutoSubscriptionCharged(TOKEN_ID);
        subNFT.chargeAutoSubscription(TOKEN_ID);

        uint256 user1BalanceAfter = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceAfter = testERC20.balanceOf(serviceProvider);

        assertEq(subNFT.expiresAt(TOKEN_ID), DEFAULT_INTERVAL * 1 + 1);
        assertEq(user1BalanceAfter, user1BalanceBefore - DEFAULT_PRICE);
        assertEq(serviceProviderBalanceAfter, serviceProviderBalanceBefore + DEFAULT_PRICE);

        (uint160 amount, uint48 expiration, uint48 nonce) =
            permit2.allowance(users[0], address(testERC20), address(subNFT));
        // 1 month of subscription is charged so deduct 1 month
        assertEq(amount, DEFAULT_PRICE * DEFAULT_NUM_OF_INTERVALS - DEFAULT_PRICE);
        assertEq(expiration, block.timestamp + DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS - 1);
        assertEq(nonce, DEFAULT_NONCE + 1);
    }

    function testChargeAutoSubscription_ChargeAgainAfter1Month() public {
        testChargeAutoSubscription();

        assertEq(subNFT.getSubscriptionDetails(TOKEN_ID).expiryTs, 1 + 30 days);
        vm.warp(1 + 30 days + 1);

        uint256 user1BalanceBefore = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceBefore = testERC20.balanceOf(serviceProvider);

        vm.prank(users[1]);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.AutoSubscriptionCharged(TOKEN_ID);
        subNFT.chargeAutoSubscription(TOKEN_ID);

        uint256 user1BalanceAfter = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceAfter = testERC20.balanceOf(serviceProvider);

        assertEq(subNFT.expiresAt(TOKEN_ID), DEFAULT_INTERVAL * 2 + 1 + 1);
        assertEq(user1BalanceAfter, user1BalanceBefore - DEFAULT_PRICE);
        assertEq(serviceProviderBalanceAfter, serviceProviderBalanceBefore + DEFAULT_PRICE);
    }

    function testChargeAutoSubscription_RevertWhenTokenIdDoesNotExist() public {
        vm.prank(users[0]);
        vm.expectRevert(ISubNFT.InvalidTokenId.selector);
        subNFT.chargeAutoSubscription(TOKEN_ID + 10);
    }

    function testChargeAutoSubscription_RevertWhenChargeTooEarly() public {
        testChargeAutoSubscription();

        vm.prank(users[1]);
        vm.expectRevert(ISubNFT.ChargeTooEarly.selector);
        subNFT.chargeAutoSubscription(TOKEN_ID);
    }

    function testChargeAutoSubscription_RevertWhenUsersHaveNoMoney() public {
        testChargeAutoSubscription();

        assertEq(subNFT.getSubscriptionDetails(TOKEN_ID).expiryTs, 1 + 30 days);
        vm.warp(1 + 30 days + 1);

        // send all ERC20 to user2 so user1 has no money
        vm.startPrank(users[0]);
        testERC20.transfer(users[1], testERC20.balanceOf(users[0]));
        vm.stopPrank();

        vm.prank(users[1]);
        vm.expectRevert(ISubNFT.TransferFailed.selector);
        subNFT.chargeAutoSubscription(TOKEN_ID);
    }

    function testCancelAutoSubscription() public {
        vm.prank(users[0]);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.AutoSubscriptionCancelled(TOKEN_ID);
        subNFT.cancelAutoSubscription(TOKEN_ID);
    }

    function testIsRenewable_ReturnFalseWhenInvalidToken() public view {
        assertEq(subNFT.isRenewable(TOKEN_ID2), false);
    }

    function testExpiresAt() public {
        assertEq(subNFT.expiresAt(TOKEN_ID), 0);
        vm.startPrank(users[0]);
        testERC20.approve(address(subNFT), type(uint256).max);
        subNFT.renewSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);
        assertEq(subNFT.expiresAt(TOKEN_ID), DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS);

        subNFT.cancelAutoSubscription(TOKEN_ID);
        assertEq(subNFT.expiresAt(TOKEN_ID), DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS);
    }

    function testExpiresAt_ReturnZeroWhenInvalidToken() public view {
        assertEq(subNFT.expiresAt(TOKEN_ID2), 0);
    }

    function testGetRenewalPrice() public view {
        assertEq(
            subNFT.getRenewalPrice(DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS), DEFAULT_PRICE * DEFAULT_NUM_OF_INTERVALS
        );
    }

    function testGetRenewalPrice_ReturnZeroWhenInvalidPlanIdx() public view {
        assertEq(subNFT.getRenewalPrice(DEFAULT_PLAN_IDX + 1, DEFAULT_NUM_OF_INTERVALS), 0);
    }

    function testGetSubscriptionDetails() public {
        assertEq(subNFT.getSubscriptionDetails(TOKEN_ID).expiryTs, 0);
        vm.startPrank(users[0]);
        testERC20.approve(address(subNFT), type(uint256).max);
        subNFT.renewSubscription(TOKEN_ID, DEFAULT_PLAN_IDX, DEFAULT_NUM_OF_INTERVALS);
        assertEq(subNFT.getSubscriptionDetails(TOKEN_ID).expiryTs, DEFAULT_INTERVAL * DEFAULT_NUM_OF_INTERVALS);
    }

    function testGetSubscriptionDetails_ReturnEmptySubscriptionWhenInvalidToken() public view {
        assertEq(subNFT.getSubscriptionDetails(TOKEN_ID2).planIdx, 0);
        assertEq(subNFT.getSubscriptionDetails(TOKEN_ID2).expiryTs, 0);
    }

    function testGetSubscriptionConfig() public view {
        assertEq(subNFT.getSubscriptionConfig().paymentToken, address(testERC20));
        assertEq(subNFT.getSubscriptionConfig().serviceProvider, serviceProvider);
        assertEq(subNFT.getSubscriptionConfig().intervalInSec, DEFAULT_INTERVAL);
        assertEq(subNFT.getSubscriptionConfig().planPrices[0], DEFAULT_PRICE);
    }

    function testSupportsInterface() public view {
        assertEq(subNFT.supportsInterface(type(ISubNFT).interfaceId), true);
    }
}
