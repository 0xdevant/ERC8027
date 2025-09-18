// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermit2, IAllowanceTransfer} from "@permit2/interfaces/IPermit2.sol";

import {ISubNFT} from "./ISubNFT.sol";

contract SubNFT is ERC721, ISubNFT {
    IPermit2 public immutable PERMIT2;

    mapping(uint256 tokenId => Subscription) internal _subscriptions;

    SubscriptionConfig internal _subscriptionConfig;

    constructor(
        string memory name_,
        string memory symbol_,
        SubscriptionConfig memory subscriptionConfig,
        address permit2
    ) ERC721(name_, symbol_) {
        _subscriptionConfig = subscriptionConfig;
        PERMIT2 = IPermit2(permit2);
    }

    /**
     * @dev See {IERC5643-renewSubscription}.
     */
    function renewSubscription(uint256 tokenId, uint128 planIdx, uint64 numOfIntervals) external payable virtual {
        SubscriptionConfig memory config = _subscriptionConfig;
        _ensureValidInputs(tokenId, planIdx, config.planPrices.length, numOfIntervals);

        uint256 planPrice = _calcRenewalPrice(config.planPrices[planIdx], numOfIntervals);
        if (config.paymentToken == address(0)) {
            require(msg.value == planPrice, InsufficientPayment());
            payable(config.serviceProvider).transfer(planPrice);
        } else {
            IERC20(config.paymentToken).transferFrom(msg.sender, config.serviceProvider, planPrice);
        }

        _extendSubscription(tokenId, planIdx, config.intervalInSec, numOfIntervals);
    }

    /*//////////////////////////////////////////////////////////////
                              AUTO-RENEWAL
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev See {IERC5643-signalAutoSubscription}.
     */
    function signalAutoSubscription(
        uint256 tokenId,
        uint128 planIdx,
        uint64 numOfIntervals,
        Permit2Data calldata permit2Data
    ) external virtual {
        SubscriptionConfig memory config = _subscriptionConfig;
        _ensureValidInputs(tokenId, planIdx, config.planPrices.length, numOfIntervals);

        _ensureValidPermit(
            permit2Data.permitSingle,
            config.paymentToken,
            _calcRenewalPrice(config.planPrices[planIdx], numOfIntervals),
            config.intervalInSec,
            numOfIntervals
        );

        PERMIT2.permit(msg.sender, permit2Data.permitSingle, permit2Data.signature);

        emit AutoSubscriptionSignaled(tokenId, planIdx, numOfIntervals);
    }

    /**
     * @dev See {IERC5643-chargeAutoSubscription}.
     */
    function chargeAutoSubscription(uint256 tokenId) external virtual {
        address nftOwner = _ownerOf(tokenId);
        require(nftOwner != address(0), InvalidTokenId());
        Subscription memory subscription = _subscriptions[tokenId];
        require(block.timestamp > subscription.expiryTs, ChargeTooEarly());

        SubscriptionConfig memory config = _subscriptionConfig;
        require(config.paymentToken != address(0), OnlyERC20ForAutoRenewal());

        // NOTE: only charge for one interval to keep the subscription automatic
        try PERMIT2.transferFrom(
            nftOwner, config.serviceProvider, uint160(config.planPrices[subscription.planIdx]), config.paymentToken
        ) {
            _extendSubscription(tokenId, subscription.planIdx, config.intervalInSec, 1);
            emit AutoSubscriptionCharged(tokenId);
        } catch {
            revert TransferFailed();
        }
    }

    /**
     * @dev See {IERC5643-cancelAutoSubscription}.
     */
    function cancelAutoSubscription(uint256 tokenId) external virtual {
        require(_ownerOf(tokenId) != address(0), InvalidTokenId());
        SubscriptionConfig memory config = _subscriptionConfig;
        IPermit2.TokenSpenderPair[] memory approvals = new IPermit2.TokenSpenderPair[](1);
        approvals[0] = IAllowanceTransfer.TokenSpenderPair(config.paymentToken, config.serviceProvider);

        PERMIT2.lockdown(approvals);

        emit AutoSubscriptionCancelled(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Ensures the permit is valid beforehand by making sure:
     * 1. this contract is the spender
     * 2. the payment token is the same as the allowed token
     * 3. the amount is the same as the price of the subscription plan times the number of intervals
     * 4. the expiration is greater or equal to the current timestamp + `interval * numOfIntervals`
     */
    function _ensureValidPermit(
        IPermit2.PermitSingle memory permitSingle,
        address paymentToken,
        uint256 price,
        uint64 interval,
        uint64 numOfIntervals
    ) internal virtual {
        IPermit2.PermitSingle memory permit = permitSingle;
        require(permit.details.token == paymentToken, PaymentTokenMismatch());
        require(permit.details.amount == price, InsufficientPayment());
        require(permit.details.expiration >= block.timestamp + interval * numOfIntervals, AllowanceExpireTooEarly());
        require(permit.spender == address(this), InvalidSpender());
    }

    /**
     * @dev Ensures the inputs are valid.
     * 1. the tokenId exists
     * 2. the planIdx is less than the number of plans
     * 3. the numOfIntervals is greater than 0
     */
    function _ensureValidInputs(uint256 tokenId, uint128 planIdx, uint256 numOfPlans, uint64 numOfIntervals)
        internal
        virtual
    {
        require(_ownerOf(tokenId) != address(0), InvalidTokenId());
        require(planIdx < numOfPlans, InvalidPlanIdx());
        require(numOfIntervals > 0, InvalidNumOfIntervals());
    }

    /**
     * @dev Extends the subscription for `tokenId` for `duration` seconds.
     * If the `tokenId` does not exist, an error will be thrown.
     * If a token is not renewable, an error will be thrown.
     * Emits a {SubscriptionExtended} event after the subscription is extended.
     */
    function _extendSubscription(uint256 tokenId, uint128 planIdx, uint64 interval, uint64 numOfIntervals)
        internal
        virtual
    {
        uint128 expiryTs = _subscriptions[tokenId].expiryTs;
        uint128 newExpiryTs;
        if ((expiryTs == 0) || (expiryTs < block.timestamp)) {
            newExpiryTs = uint128(block.timestamp) + interval * numOfIntervals;
        } else {
            // subscribe in the middle of the interval, as `expiresAt` must be multiples of interval so just add `interval * numOfInterval`
            require(_isRenewable(tokenId), SubscriptionNotRenewable());
            newExpiryTs = expiryTs + interval * numOfIntervals;
        }

        _subscriptions[tokenId] = Subscription({planIdx: planIdx, expiryTs: newExpiryTs});

        emit SubscriptionExtended(tokenId, planIdx, newExpiryTs);
    }

    /**
     * @dev Internal function to set the subscription config.
     */
    function _setSubscriptionConfig(SubscriptionConfig calldata subscriptionConfig) internal virtual {
        _subscriptionConfig = subscriptionConfig;
    }

    /**
     * @dev Calculates the price to renew a subscription for `numOfIntervals` * `interval` seconds for
     * a given tokenId.
     */
    function _calcRenewalPrice(uint256 price, uint64 numOfIntervals) internal pure virtual returns (uint256) {
        return price * numOfIntervals;
    }

    /**
     * @dev Internal function to determine renewability. Implementing contracts
     * should override this function if renewabilty should be disabled for all or
     * some tokens.
     */
    function _isRenewable(uint256 tokenId) internal view virtual returns (bool) {
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev See {IERC5643-isRenewable}.
     */
    function isRenewable(uint256 tokenId) external view virtual returns (bool) {
        if (_ownerOf(tokenId) == address(0)) return false;
        return _isRenewable(tokenId);
    }

    /**
     * @dev See {IERC5643-expiresAt}.
     */
    function expiresAt(uint256 tokenId) external view virtual returns (uint128) {
        if (_ownerOf(tokenId) == address(0)) return 0;
        return _subscriptions[tokenId].expiryTs;
    }

    /**
     * @dev See {IERC5643-getRenewalPrice}.
     */
    function getRenewalPrice(uint128 planIdx, uint64 numOfIntervals) external view virtual returns (uint256) {
        if (numOfIntervals == 0 || planIdx >= _subscriptionConfig.planPrices.length) return 0;
        return _calcRenewalPrice(_subscriptionConfig.planPrices[planIdx], numOfIntervals);
    }

    /**
     * @dev See {IERC5643-getSubscriptionDetails}.
     */
    function getSubscriptionDetails(uint256 tokenId) external view virtual returns (Subscription memory) {
        if (_ownerOf(tokenId) == address(0)) return Subscription({planIdx: 0, expiryTs: 0});
        return _subscriptions[tokenId];
    }

    /**
     * @dev See {IERC5643-getSubscriptionConfig}.
     */
    function getSubscriptionConfig() external view virtual returns (SubscriptionConfig memory) {
        return _subscriptionConfig;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ISubNFT).interfaceId || super.supportsInterface(interfaceId);
    }
}
