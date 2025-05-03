// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17; // Match contract pragma

import {Script, console} from "forge-std/Script.sol";
import {FireballDrop} from "../src/FireballDrop.sol";
import {HelperConfig} from "./HelperConfig.s.sol"; // We'll create this helper

contract DeployFireballDrop is Script {
    function run() external returns (FireballDrop) {
        // Load deployment configuration
        HelperConfig helperConfig = new HelperConfig();
        (
            address vrfWrapperAddress,
            address linkTokenAddress,
            uint32 callbackGasLimit,
            uint16 initialPlatformFeePercent,
            address feeReceiverAddress,
            uint256 deployerPrivateKey
        ) = helperConfig.activeNetworkConfig();

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying FireballDrop contract...");
        console.log("----------------------------------------------------");
        console.log("Using VRF Wrapper:", vrfWrapperAddress);
        console.log("Using LINK Token:", linkTokenAddress);
        console.log("Callback Gas Limit:", callbackGasLimit);
        console.log("Initial Platform Fee:", initialPlatformFeePercent, "basis points");
        console.log("Fee Receiver:", feeReceiverAddress);
        console.log("----------------------------------------------------");

        // Deploy the contract
        FireballDrop fireballDrop = new FireballDrop(
            vrfWrapperAddress,
            linkTokenAddress,
            callbackGasLimit,
            initialPlatformFeePercent,
            feeReceiverAddress
        );

        // Stop broadcasting
        vm.stopBroadcast();

        console.log(unicode"✅ FireballDrop deployed to:", address(fireballDrop));

        // --- Post-Deployment Steps (Important!) ---
        console.log("\n--- Important Next Steps ---");
        console.log("1. Fund the contract with LINK tokens for VRF requests.");
        console.log("2. Fund the contract with native currency (e.g., ETH) for native payment VRF.");
        console.log("   - Send ETH/Native currency to the contract address:", address(fireballDrop));
        console.log("3. If you didn't use the deployer as the fee receiver, verify the feeReceiverAddress is correct.");
        console.log("4. Consider verifying the contract on the block explorer.");
        console.log("----------------------------------------------------");

        return fireballDrop;
    }
}
