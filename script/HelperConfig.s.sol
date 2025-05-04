// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";

contract HelperConfig is Script {
    // Struct to hold network-specific configuration
    struct NetworkConfig {
        address vrfWrapperAddress;
        address linkTokenAddress;
        uint32 callbackGasLimit;
        uint16 initialPlatformFeePercent; // Basis points (100 = 1%)
        address feeReceiverAddress; // Address to receive platform fees
    }

    // Active network configuration
    NetworkConfig public activeNetworkConfig;

    constructor() {
        // --- Sepolia Testnet Configuration ---
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        }
        // --- Add other networks like Mainnet, Polygon, etc. here ---
        else if (block.chainid == 84532) { // base sepolia Mainnet
          activeNetworkConfig = getBaseSepoliaConfig();
         }
        else if (block.chainid == 8453) { // base Mainnet
         activeNetworkConfig = getBaseConfig();
        }
        else {
            // Default to Sepolia or throw an error if preferred
            console.log("Warning: Chain ID not recognized, defaulting to Sepolia config. Set config for chain ID:", block.chainid);
            activeNetworkConfig = getSepoliaConfig();
            // Alternatively, uncomment the next line to make deployment fail on unknown networks
            // revert("Unsupported Chain ID");
        }
    }

    // --- Configuration Functions for Different Networks ---

    function getSepoliaConfig() internal view returns (NetworkConfig memory) {
        
        address _vrfWrapper = 0x195f15F2d49d693cE265b4fB0fdDbE15b1850Cc1;
        address _linkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

        return NetworkConfig({
            vrfWrapperAddress:  _vrfWrapper,
            linkTokenAddress: address(_linkToken),
            callbackGasLimit: uint32(300000), // Default 90k gas
            initialPlatformFeePercent: uint16(100), // Default 1%
            feeReceiverAddress: vm.envAddress("FEE_RECEIVER_ADDRESS") // Default to deployer if not set
        });
    }


    function getBaseSepoliaConfig() internal view returns (NetworkConfig memory) {
        address _vrfWrapper = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;
        address _linkToken = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
        return NetworkConfig({
            vrfWrapperAddress:  _vrfWrapper,
            linkTokenAddress: _linkToken,
            callbackGasLimit:  uint32(300000), // Default 90k gas
            initialPlatformFeePercent:  uint16(100), // Default 1%
            feeReceiverAddress: vm.envAddress("FEE_RECEIVER_ADDRESS") // Default to deployer if not set
        });
    }
    function getBaseConfig() internal view returns (NetworkConfig memory) {
        address _vrfWrapper = 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196;
        address _linkToken = 0xb0407dbe851f8318bd31404A49e658143C982F23;
        return NetworkConfig({
            vrfWrapperAddress:  _vrfWrapper,
            linkTokenAddress: _linkToken,
            callbackGasLimit: uint32(vm.envUint("BASE_CALLBACK_GAS_LIMIT")), // Default 90k gas
            initialPlatformFeePercent: uint16(vm.envUint("PLATFORM_FEE_PERCENT")), // Default 1%
            feeReceiverAddress: vm.envAddress("FEE_RECEIVER_ADDRESS") // Default to deployer if not set
        });
    }


    // --- Helper to get deployer address and private key ---

    function getDeployerInfo() internal view returns (address deployerAddress, uint256 deployerPrivateKey) {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        if (deployerPrivateKey == 0) {
            revert("PRIVATE_KEY environment variable not set. Set it in your .env file or environment.");
        }
        deployerAddress = vm.addr(deployerPrivateKey);
    }

    // --- Combined function to get all necessary config for the active network ---

    function getActiveNetworkConfig()
        public
        view
        returns (address, address, uint32, uint16, address, uint256)
    {
        (address deployerAddress, uint256 deployerPrivateKey) = getDeployerInfo();
        // Use deployer address as fee receiver if not specified in env
        address feeReceiver = activeNetworkConfig.feeReceiverAddress == address(0) ? deployerAddress : activeNetworkConfig.feeReceiverAddress;
        return (
            activeNetworkConfig.vrfWrapperAddress,
            activeNetworkConfig.linkTokenAddress,
            activeNetworkConfig.callbackGasLimit,
            activeNetworkConfig.initialPlatformFeePercent,
            feeReceiver,
            deployerPrivateKey
        );
    }
}