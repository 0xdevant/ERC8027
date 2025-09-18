// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {SubNFT, ISubNFT} from "src/SubNFT.sol";

contract DeployScript is Script {
    SubNFT public subNFT;

    function run() public {
        vm.startBroadcast();

        string memory name = "Mock SubNFT";
        string memory symbol = "MSNFT";

        uint64 intervalInSec = 30 days; // 1 month per cycle
        uint256[] memory planPrices = new uint256[](1);

        address USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        // NOTE: use respective Permit2 address for the chain you want to deploy on
        address PERMIT2_MAINNET = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        // NOTE: specify the service provider address here
        address serviceProvider = address(0);

        planPrices[0] = 100 * 10 ** IERC20(USDC_MAINNET).decimals();
        ISubNFT.SubscriptionConfig memory subscriptionConfig = ISubNFT.SubscriptionConfig({
            paymentToken: USDC_MAINNET,
            serviceProvider: serviceProvider,
            intervalInSec: intervalInSec,
            planPrices: planPrices
        });

        require(
            USDC_MAINNET != address(0) && PERMIT2_MAINNET != address(0) && serviceProvider != address(0)
                && intervalInSec != 0 && planPrices.length > 0,
            "Zero input"
        );

        subNFT = new SubNFT(name, symbol, subscriptionConfig, PERMIT2_MAINNET);

        vm.stopBroadcast();

        console.log("SubNFT deployed to:", address(subNFT));
    }
}
