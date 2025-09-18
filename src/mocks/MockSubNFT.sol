// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SubNFT} from "../SubNFT.sol";

contract MockSubNFT is Ownable, SubNFT {
    bool renewable;

    constructor(
        string memory name_,
        string memory symbol_,
        SubscriptionConfig memory subscriptionConfig,
        address permit2
    ) SubNFT(name_, symbol_, subscriptionConfig, permit2) Ownable(msg.sender) {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function mintWithSubscription(address to, uint256 tokenId, uint128 planIdx, uint64 numOfIntervals) public {
        _mint(to, tokenId);
        _extendSubscription(tokenId, planIdx, _subscriptionConfig.intervalInSec, numOfIntervals);
    }

    function _isRenewable(uint256) internal view override returns (bool) {
        return renewable;
    }

    function setRenewable(bool _renewable) external onlyOwner {
        renewable = _renewable;
    }

    function setSubscriptionConfig(SubscriptionConfig calldata subscriptionConfig) external onlyOwner {
        _setSubscriptionConfig(subscriptionConfig);
    }

    /**
     * @dev This function is used soley for testing purposes and shouldn't be used
     * in a standalone fashion.
     */
    function extendSubscription(uint256 tokenId, uint128 planIdx, uint64 numOfIntervals) external {
        _extendSubscription(tokenId, planIdx, _subscriptionConfig.intervalInSec, numOfIntervals);
    }
}
