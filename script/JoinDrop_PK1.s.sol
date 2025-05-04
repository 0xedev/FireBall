// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {FireballDrop} from "../src/FireballDrop.sol";

contract JoinDropPk1 is Script {
    // --- Configuration ---
    // The deployed FireballDrop contract address
    address constant CONTRACT_ADDRESS = 0x786190c74E45DF73b6fd8b61A9664bCB855e6DdB;
    // !!! SET THIS TO THE ID OF THE DROP YOU WANT TO JOIN !!!
    uint256 constant DROP_ID_TO_JOIN = 0; // Example: Joining Drop 0
    // The name this participant will use
    string constant PARTICIPANT_NAME = "Participant One";
    // The environment variable holding the private key for this participant
    string constant PRIVATE_KEY_ENV_VAR = "PRIVATE_KEY_1";
    // --- End Configuration ---

    function run() external {
        // Get the private key from environment variables
        string memory privateKey = vm.envString(PRIVATE_KEY_ENV_VAR);
        require(bytes(privateKey).length > 0, "Private key env var not set");

        // Get contract instance
        FireballDrop fireballDrop = FireballDrop(payable(CONTRACT_ADDRESS));

        // Get drop info to determine entry fee
        (,,,,,,,,,, address[] memory winners) = fireballDrop.getDropInfo(DROP_ID_TO_JOIN);
        (, uint256 entryFee,,,,,,,,,) = fireballDrop.getDropInfo(DROP_ID_TO_JOIN); // Fetch entryFee separately to avoid stack issues

        console.log("Attempting to join Drop ID:", DROP_ID_TO_JOIN);
        console.log("  Participant Name:", PARTICIPANT_NAME);
        console.log("  Using Private Key from env:", PRIVATE_KEY_ENV_VAR);
        console.log("  Required Entry Fee (wei):", entryFee);

        vm.startBroadcast(vm.deriveKey(privateKey, 0));

        // Call joinDrop, sending the entryFee as msg.value
        fireballDrop.joinDrop{value: entryFee}(DROP_ID_TO_JOIN, PARTICIPANT_NAME);

        vm.stopBroadcast();

        console.log(unicode"✅ Join Drop transaction sent for", PARTICIPANT_NAME);
    }
}