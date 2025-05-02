// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./FireballDrop.sol";

/**
 * @title FireballDropFactory
 * @dev A factory contract for deploying FireballDrop contracts with Chainlink VRF v2.5 Direct Funding
 */
contract FireballDropFactory is Ownable {
    // Chainlink VRF parameters
    address public immutable wrapperAddress; // VRF v2.5 Wrapper address
    address public immutable linkAddress; // LINK token address
    uint32 public immutable callbackGasLimit;

    // Platform fee percentage (in basis points, 100 = 1%)
    uint16 public platformFeePercent;
    address public immutable feeReceiver;

    // Array to store deployed FireballDrop contracts
    address[] public deployedDrops;

    // Events
    event DropDeployed(address indexed dropAddress, uint256 indexed dropId, uint16 platformFeePercent);
    event PlatformFeeUpdated(uint16 newFeePercent);

    /**
     * @dev Constructor
     * @param _wrapperAddress address of the VRF v2.5 Wrapper
     * @param _linkAddress address of the LINK token
     * @param _callbackGasLimit gas limit for VRF callback
     * @param _platformFeePercent initial platform fee percentage in basis points
     * @param _feeReceiver address to receive platform fees
     */
    constructor(
        address _wrapperAddress,
        address _linkAddress,
        uint32 _callbackGasLimit,
        uint16 _platformFeePercent,
        address _feeReceiver
    ) Ownable(msg.sender) {
        require(_wrapperAddress != address(0), "Invalid wrapper address");
        require(_linkAddress != address(0), "Invalid LINK address");
        require(_feeReceiver != address(0), "Invalid fee receiver");
        require(_platformFeePercent <= 1000, "Fee too high"); // Max 10%

        wrapperAddress = _wrapperAddress;
        linkAddress = _linkAddress;
        callbackGasLimit = _callbackGasLimit;
        platformFeePercent = _platformFeePercent;
        feeReceiver = _feeReceiver;
    }

    /**
     * @dev Deploy a new FireballDrop contract
     * @return dropAddress The address of the deployed FireballDrop contract
     */
    function deployDrop() external returns (address dropAddress) {
        FireballDrop newDrop = new FireballDrop(
            wrapperAddress,
            linkAddress,
            callbackGasLimit,
            platformFeePercent,
            feeReceiver
        );
        dropAddress = address(newDrop);
        deployedDrops.push(dropAddress);

        emit DropDeployed(dropAddress, deployedDrops.length - 1, platformFeePercent);
        return dropAddress;
    }

    /**
     * @dev Update the platform fee percentage for future deployments
     * @param newFeePercent New platform fee percentage in basis points
     */
    function updatePlatformFee(uint16 newFeePercent) external onlyOwner {
        require(newFeePercent <= 1000, "Fee too high"); // Max 10%
        platformFeePercent = newFeePercent;
        emit PlatformFeeUpdated(newFeePercent);
    }

    /**
     * @dev Get the list of deployed FireballDrop contracts
     * @return Array of deployed FireballDrop addresses
     */
    function getDeployedDrops() external view returns (address[] memory) {
        return deployedDrops;
    }

    /**
     * @dev Get the number of deployed FireballDrop contracts
     * @return Number of deployed drops
     */
    function getDropCount() external view returns (uint256) {
        return deployedDrops.length;
    }
}