// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPermit2} from "@permit2/interfaces/IPermit2.sol";

interface ISubNFT {
    /// @param paymentToken Token to pay for the subscription, use address(0) for native token
    /// @param serviceProvider The address of the service provider to receive the payment
    /// @param interval The interval of each subscription e.g. 30 days in seconds
    /// @param planPrices Array of prices for different plans, the respective index of the price refers to `planIdx`,
    /// length > 1 indicates multiple plans available
    struct SubscriptionConfig {
        address paymentToken;
        address serviceProvider;
        uint64 intervalInSec;
        uint256[] planPrices;
    }

    /// @param planIdx The index of the subscription plan from `planPrices`
    /// @param expiryTs The latest timestamp which the subscription is valid until
    struct Subscription {
        uint128 planIdx;
        uint128 expiryTs;
    }

    /// @notice A packed input to consist details of the permit and its signature
    struct Permit2Data {
        IPermit2.PermitSingle permitSingle;
        bytes signature;
    }

    /// @notice Thrown when paymentToken is address(0) but not enough native token is sent as msg.value
    error InsufficientPayment();
    /// @notice Thrown when the subscription is not renewable for all tokens or a given tokenId
    error SubscriptionNotRenewable();
    /// @notice Thrown when the tokenId does not exist
    error InvalidTokenId();
    /// @notice Thrown when the number of intervals is not greater than 0
    error InvalidNumOfIntervals();
    /// @notice Thrown when the plan index exceeds the number of plans
    error InvalidPlanIdx();
    /// @notice Thrown when the token specified in the permit is not same as the payment token
    error PaymentTokenMismatch();
    /// @notice Thrown when the expiration of the permit doesn't last until the current timestamp + `interval * numOfIntervals`
    error AllowanceExpireTooEarly();
    /// @notice Thrown when the spender of the permit is not this contract
    error InvalidSpender();
    /// @notice Thrown when the service provider charges before the `expiryTs` of the subscriber's subscription
    error ChargeTooEarly();
    /// @notice Thrown when the service provider charges for subscription that uses native token as `paymentToken` in `SubscriptionConfig`
    error OnlyERC20ForAutoRenewal();
    /// @notice Thrown when the service provider charges for subscription but either the user has not enough allowance or not enough payment tokens
    error TransferFailed();

    /// @notice Emitted when a subscription is extended
    /// @dev When a subscription is extended, the expiration timestamp is extended for `interval * numOfIntervals`
    /// @param tokenId The NFT to extend the subscription for
    /// @param planIdx The plan index to indicate which plan to extend the subscription for
    /// @param expiryTs The new expiration timestamp of the subscription
    event SubscriptionExtended(uint256 indexed tokenId, uint128 planIdx, uint128 expiryTs);

    /// @notice Emitted when a user signals a subscription by signing a permit2 permit
    /// @param tokenId The NFT to signal the subscription for
    /// @param planIdx The plan index to indicate which plan to signal the subscription for
    /// @param numOfIntervals The number of `interval` the user intends to subscribe for
    event AutoSubscriptionSignaled(uint256 indexed tokenId, uint128 planIdx, uint64 numOfIntervals);

    /// @notice Emitted when service provider charges a user for an auto subscription
    /// @dev When a auto subscription is charged, the expiration timestamp is extended for ONE `interval` only
    /// @param tokenId The NFT to charge the auto subscription for
    event AutoSubscriptionCharged(uint256 indexed tokenId);

    /// @notice Emitted when a user cancels the upcoming subscription by revoking permit2 allowance
    /// @dev When a subscription is canceled, the subscription will last until the `expiryTs` timestamp
    /// @param tokenId The NFT to cancel the auto subscription for
    event AutoSubscriptionCancelled(uint256 indexed tokenId);

    /// @notice Manually renews a subscription for an NFT by directly transferring native token or ERC20 token to the service provider
    /// @dev Throws if `tokenId` does not exist
    /// @dev Throws if `planIdx` is not a valid plan index
    /// @dev Throws if `numOfIntervals` is not greater than 0
    /// @dev Throws if the payment is insufficient
    /// @param tokenId The NFT to renew the subscription for
    /// @param planIdx The plan index to indicate which plan to subscribe to
    /// @param numOfIntervals The number of `interval` to extend the subscription for
    function renewSubscription(uint256 tokenId, uint128 planIdx, uint64 numOfIntervals) external payable;

    /// @notice Signals an intent for recurring subscription for an NFT by signing a permit2 permit
    /// @dev When a subscription is signaled, the subscription is not active yet, it indicates the user has approved the contract
    /// to let the service provider charge subscription fee automatically by `interval * numOfIntervals`
    /// @dev Throws if `tokenId` does not exist
    /// @dev Throws if `planIdx` is not a valid plan index
    /// @dev Throws if `numOfIntervals` is not greater than 0
    /// @dev Throws if the expiration of the permit doesn't last until the current timestamp + `interval * numOfIntervals`
    /// @param tokenId The NFT to signal the subscription for
    /// @param planIdx The plan index to indicate which plan to signal the subscription for
    /// @param numOfIntervals The number of `interval` to signal the subscription for
    /// @param permit2Data Data that consists of details of the permit and its signature
    function signalAutoSubscription(
        uint256 tokenId,
        uint128 planIdx,
        uint64 numOfIntervals,
        Permit2Data calldata permit2Data
    ) external;

    /// @notice Charges the subscription for an NFT by transferring ERC20 payment token
    /// from user to the service provider via Permit2, usually called by the service provider automatically
    /// after a subscription is signaled by a user, and recurringly for each `interval`
    /// @dev No access control is required for this function as the spender is restricted to this contract
    /// and receiver is restricted to the service provider
    /// @dev Throws if `tokenId` does not exist
    /// @dev Throws if charges before the `expiryTs` of the subscriber's subscription
    /// @dev Throws if the payment token is not ERC20
    /// @param tokenId The NFT to charge the subscription for
    function chargeAutoSubscription(uint256 tokenId) external;

    /// @notice Cancels the subscription of an NFT by revoking permit2 allowance
    /// @dev Throws if `tokenId` does not exist
    /// @dev When a subscription is canceled, the subscription will last until the `expiryTs` timestamp
    /// @param tokenId The NFT to cancel the subscription for
    function cancelAutoSubscription(uint256 tokenId) external;

    /// @notice Determines whether a NFT's subscription can be renewed
    /// @dev Returns false if `tokenId` does not exist
    /// @param tokenId The NFT to check the renewability of
    /// @return The renewability of a NFT's subscription
    function isRenewable(uint256 tokenId) external view returns (bool);

    /// @notice Gets the expiration date of a NFT's subscription
    /// @dev Returns 0 if `tokenId` does not exist
    /// @param tokenId The NFT to get the expiration date of
    /// @return The `expiryTs` of the NFT's subscription
    function expiresAt(uint256 tokenId) external view returns (uint128);

    /// @notice Gets the price to renew a subscription for a number of `interval` for a given tokenId.
    /// @dev Returns 0 if `numOfIntervals` is 0
    /// @dev Returns 0 if `planIdx` is not a valid plan index
    /// @param planIdx The plan index to indicate which plan to subscribe to
    /// @param numOfIntervals The number of `interval` to renew the subscription for
    /// @return The price to renew the subscription
    function getRenewalPrice(uint128 planIdx, uint64 numOfIntervals) external view returns (uint256);

    /// @notice Gets the subscription details for a given tokenId
    /// @dev Returns empty `Subscription` if `tokenId` does not exist
    /// @param tokenId The NFT to get the subscription for
    /// @return The packed struct of `Subscription`
    function getSubscriptionDetails(uint256 tokenId) external view returns (Subscription memory);

    /// @notice Gets the subscription config
    /// @return The packed struct of `SubscriptionConfig`
    function getSubscriptionConfig() external view returns (SubscriptionConfig memory);
}
