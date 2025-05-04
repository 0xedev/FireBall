// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {FireballDrop} from "../src/FireballDrop.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract CreateHostPaidDrop is Script {
    // --- Configuration ---
    // Replace with your deployed FireballDrop contract address
    address constant CONTRACT_ADDRESS = 0x68C3A6915E69e28222b79255bEde08a1f3303e84;

    // Drop Parameters
    uint256 constant REWARD_AMOUNT = 0.001 ether; // Host pays this upfront
    uint256 constant MAX_PARTICIPANTS = 4;
    uint32 constant NUM_WINNERS = 2;
    bool constant IS_MANUAL_SELECTION = false; // Automatic selection when full
    // --- End Configuration ---

    function run() external {
        // Get the deployer/host private key
        HelperConfig helperConfig = new HelperConfig();
        (,,,, address feeReceiver, uint256 deployerPrivateKey) = helperConfig.getActiveNetworkConfig();

        // Get contract instance
        FireballDrop fireballDrop = FireballDrop(payable(CONTRACT_ADDRESS));

        console.log("Creating Host-Paid Drop on contract:", address(fireballDrop));
        console.log("  Reward Amount (Paid by Host):", REWARD_AMOUNT / 1 ether, "ETH");
        console.log("  Max Participants:", MAX_PARTICIPANTS);
        console.log("  Number of Winners:", NUM_WINNERS);
        console.log("  Manual Selection:", IS_MANUAL_SELECTION);

        vm.startBroadcast(deployerPrivateKey);

        // Call createDrop with msg.value for the reward
        fireballDrop.createDrop{value: REWARD_AMOUNT}(
            0, // entryFee is 0 for host-paid
            REWARD_AMOUNT,
            MAX_PARTICIPANTS,
            false, // isPaidEntry = false
            IS_MANUAL_SELECTION,
            NUM_WINNERS
        );

        vm.stopBroadcast();

        // You might want to query the dropCounter or listen for the event to get the new dropId
        console.log(unicode"✅ Host-Paid Drop creation transaction sent.");
        console.log("   Query the contract events or dropCounter to find the new dropId.");
    }
}