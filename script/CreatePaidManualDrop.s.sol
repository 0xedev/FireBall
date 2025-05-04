// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {FireballDrop} from "../src/FireballDrop.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract CreatePaidManualDrop is Script {
    // --- Configuration ---
    // Replace with your deployed FireballDrop contract address
    address constant CONTRACT_ADDRESS = 0x68C3A6915E69e28222b79255bEde08a1f3303e84;

    // Drop Parameters
    uint256 constant ENTRY_FEE = 0.001 ether; // Participants pay this
    uint256 constant MAX_PARTICIPANTS = 4;
    uint32 constant NUM_WINNERS = 2;
    bool constant IS_MANUAL_SELECTION = true; // Host must trigger selection
    // --- End Configuration ---

    function run() external {
        // Get the deployer/host private key
        HelperConfig helperConfig = new HelperConfig();
        (,,,, address feeReceiver, uint256 deployerPrivateKey) = helperConfig.getActiveNetworkConfig();

        // Get contract instance
        FireballDrop fireballDrop = FireballDrop(payable(CONTRACT_ADDRESS));

        // Calculate required rewardAmount based on entry fee and max participants
        uint256 rewardAmount = ENTRY_FEE * MAX_PARTICIPANTS;

        console.log("Creating Participant-Paid (Manual Selection) Drop on contract:", address(fireballDrop));
        console.log("  Entry Fee:", ENTRY_FEE / 1 ether, "ETH");
        console.log("  Max Participants:", MAX_PARTICIPANTS);
        console.log("  Potential Reward Amount:", rewardAmount / 1 ether, "ETH");
        console.log("  Number of Winners:", NUM_WINNERS);
        console.log("  Manual Selection:", IS_MANUAL_SELECTION);

        vm.startBroadcast(deployerPrivateKey);

        // Call createDrop (no value sent as host isn't paying upfront)
        fireballDrop.createDrop(ENTRY_FEE, rewardAmount, MAX_PARTICIPANTS, true, IS_MANUAL_SELECTION, NUM_WINNERS);

        vm.stopBroadcast();

        console.log(unicode"✅ Participant-Paid (Manual Selection) Drop creation transaction sent.");
        console.log("   Query the contract events or dropCounter to find the new dropId.");
    }
}