// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol"; // Ensure this path is correct
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";


/**
 * @title FireballDrop
 * @dev A smart contract for hosting drop auctions with Chainlink VRF v2.5 Direct Funding, allowing host-funded or participant-paid rewards
 */
contract FireballDrop is Ownable, ReentrancyGuard, VRFV2PlusWrapperConsumerBase {
    // Chainlink VRF constants
    address public immutable linkAddress; // LINK token address
    uint32 public immutable callbackGasLimit;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant MAX_NUM_WORDS = 3; // Max winners supported

    // Platform fee percentage (in basis points, 100 = 1%), set by factory
    uint16 public immutable platformFeePercent;
    address public immutable feeReceiver;
    
    // Structure to store participant information
    struct Participant {
        address userAddress;
        string name;
        bool hasJoined;
    }
    
    // Structure to store drop information
    struct Drop {
        uint256 dropId;
        address host;
        uint256 entryFee; // In wei (ETH), 0 if host-funded
        uint256 rewardAmount; // Total reward provided by host or collected
        uint256 maxParticipants;
        uint256 currentParticipants;
        bool isActive;
        bool isCompleted;
        bool isPaidEntry; // True if participants pay, false if host funds
        uint32 numWinners; // 1, 2, or 3 winners
        address[] winners; // Array of winner addresses
        mapping(address => bool) participants;
        mapping(uint256 => address) participantAddresses;
        mapping(address => string) participantNames;
    }
    
    // Mapping to store drops
    mapping(uint256 => Drop) public drops;
    uint256 public dropCounter;
    
    // Mapping from requestId to dropId
    mapping(uint256 => uint256) private s_requestIdToDropId;
    
    // Events
    event DropCreated(uint256 indexed dropId, address indexed host, uint256 entryFee, uint256 rewardAmount, uint256 maxParticipants, bool isPaidEntry, uint32 numWinners);
    event ParticipantJoined(uint256 indexed dropId, address indexed participant, string name);
    event WinnersSelected(uint256 indexed dropId, address[] winners, uint256 prizePerWinner);
    event RequestSent(uint256 indexed requestId, uint32 numWords);
    event RequestFulfilled(uint256 indexed requestId, uint256[] randomWords, uint256 payment);
    
    /**
     * @dev Constructor
     * @param _wrapperAddress address of the VRF v2.5 Wrapper
     * @param _linkAddress address of the LINK token
     * @param _callbackGasLimit gas limit for the VRF callback
     * @param _platformFeePercent platform fee percentage in basis points
     * @param _feeReceiver address to receive platform fees
     */
    constructor(
        address _wrapperAddress,
        address _linkAddress,
        uint32 _callbackGasLimit,
        uint16 _platformFeePercent,
        address _feeReceiver
    ) VRFV2PlusWrapperConsumerBase(_wrapperAddress)  Ownable(msg.sender) {
        require(_feeReceiver != address(0), "Invalid fee receiver");
        require(_wrapperAddress != address(0), "Invalid wrapper address");
        require(_linkAddress != address(0), "Invalid LINK address");
        require(_platformFeePercent <= 1000, "Fee too high"); // Max 10%
        
        linkAddress = _linkAddress;
        callbackGasLimit = _callbackGasLimit;
        platformFeePercent = _platformFeePercent;
        feeReceiver = _feeReceiver;
    }
    
    /**
     * @dev Create a new drop
     * @param entryFee The fee to join the drop in wei (0 if host-funded)
     * @param rewardAmount The total reward for winners (host-funded or collected)
     * @param maxParticipants Maximum number of participants
     * @param isPaidEntry True if participants pay, false if host funds
     * @param numWinners Number of winners (1, 2, or 3)
     */
    function createDrop(
        uint256 entryFee,
        uint256 rewardAmount,
        uint256 maxParticipants,
        bool isPaidEntry,
        uint32 numWinners
    ) external payable {
        require(maxParticipants > numWinners, "Need more participants than winners");
        require(numWinners >= 1 && numWinners <= MAX_NUM_WORDS, "Invalid number of winners");
        if (isPaidEntry) {
            require(entryFee > 0, "Entry fee must be greater than 0");
            require(rewardAmount == entryFee * maxParticipants, "Reward must match entry fees");
        } else {
            require(entryFee == 0, "Entry fee must be 0 for host-funded");
            require(rewardAmount > 0, "Reward amount must be greater than 0");
            require(msg.value == rewardAmount, "Incorrect ETH amount sent");
        }
        
        uint256 dropId = dropCounter;
        Drop storage newDrop = drops[dropId];
        
        newDrop.dropId = dropId;
        newDrop.host = msg.sender;
        newDrop.entryFee = entryFee;
        newDrop.rewardAmount = rewardAmount;
        newDrop.maxParticipants = maxParticipants;
        newDrop.isActive = true;
        newDrop.isCompleted = false;
        newDrop.isPaidEntry = isPaidEntry;
        newDrop.numWinners = numWinners;
        newDrop.winners = new address[](numWinners);
        
        emit DropCreated(dropId, msg.sender, entryFee, rewardAmount, maxParticipants, isPaidEntry, numWinners);
        
        dropCounter++;
    }
    
    /**
     * @dev Join a drop (pay entry fee if required)
     * @param dropId The ID of the drop to join
     * @param name The name to display for the participant
     */
    function joinDrop(uint256 dropId, string memory name) external payable nonReentrant {
        Drop storage drop = drops[dropId];
        
        require(drop.isActive, "Drop is not active");
        require(!drop.isCompleted, "Drop is already completed");
        require(!drop.participants[msg.sender], "Already joined this drop");
        require(drop.currentParticipants < drop.maxParticipants, "Drop is full");
        require(bytes(name).length > 0, "Name cannot be empty");
        
        if (drop.isPaidEntry) {
            require(msg.value == drop.entryFee, "Incorrect ETH amount sent");
        } else {
            require(msg.value == 0, "No payment required");
        }
        
        // Update drop data
        drop.participants[msg.sender] = true;
        drop.participantAddresses[drop.currentParticipants] = msg.sender;
        drop.participantNames[msg.sender] = name;
        drop.currentParticipants++;
        if (drop.isPaidEntry) {
            drop.rewardAmount += msg.value;
        }
        
        emit ParticipantJoined(dropId, msg.sender, name);
        
        // Auto-select winners when drop is full
        if (drop.currentParticipants == drop.maxParticipants) {
            requestRandomWinners(dropId);
        }
    }
    
    /**
     * @dev Request random numbers to select winners
     * @param dropId The ID of the drop
     */
    function requestRandomWinners(uint256 dropId) public {
        Drop storage drop = drops[dropId];
        
        require(msg.sender == drop.host || msg.sender == owner() || drop.currentParticipants == drop.maxParticipants, 
            "Only host, owner, or full drop can request winners");
        require(drop.isActive, "Drop is not active");
        require(!drop.isCompleted, "Drop is already completed");
        require(drop.currentParticipants >= drop.numWinners, "Need more participants than winners");
        
        // Deactivate the drop
        drop.isActive = false;
        
        // Request randomness with native payment
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
        );
        (uint256 requestId, uint256 reqPrice) = requestRandomnessPayInNative(
            callbackGasLimit,
            REQUEST_CONFIRMATIONS,
            drop.numWinners,
            extraArgs
        );
        
        s_requestIdToDropId[requestId] = dropId;
        emit RequestSent(requestId, drop.numWinners);
    }
    
    /**
     * @dev Callback function used by VRF Wrapper
     * @param _requestId - id of the request
     * @param _randomWords - array of random results from VRF Wrapper
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        uint256 dropId = s_requestIdToDropId[_requestId];
        Drop storage drop = drops[dropId];
        
        require(!drop.isCompleted, "Drop already completed");
        
        // Select winners using random numbers
        for (uint32 i = 0; i < drop.numWinners; i++) {
            uint256 winnerIndex = _randomWords[i] % drop.currentParticipants;
            drop.winners[i] = drop.participantAddresses[winnerIndex];
        }
        
        // Calculate platform fee and prize per winner
        uint256 platformFee = (drop.rewardAmount * platformFeePercent) / 10000;
        uint256 totalPrize = drop.rewardAmount - platformFee;
        uint256 prizePerWinner = totalPrize / drop.numWinners;
        
        // Transfer platform fee
        if (platformFee > 0) {
            (bool feeSuccess, ) = feeReceiver.call{value: platformFee}("");
            require(feeSuccess, "Platform fee transfer failed");
        }
        
        // Transfer prize to each winner
        for (uint32 i = 0; i < drop.numWinners; i++) {
            (bool prizeSuccess, ) = drop.winners[i].call{value: prizePerWinner}("");
            require(prizeSuccess, "Prize transfer failed");
        }
        
        // Mark drop as completed
        drop.isCompleted = true;
        
        emit RequestFulfilled(_requestId, _randomWords, platformFee);
        emit WinnersSelected(dropId, drop.winners, prizePerWinner);
    }
    
    /**
     * @dev Get participant information for a drop
     * @param dropId The ID of the drop
     * @return addresses Array of participant addresses
     * @return names Array of participant names
     */
    function getDropParticipants(uint256 dropId) external view returns (address[] memory addresses, string[] memory names) {
        Drop storage drop = drops[dropId];
        
        addresses = new address[](drop.currentParticipants);
        names = new string[](drop.currentParticipants);
        
        for (uint256 i = 0; i < drop.currentParticipants; i++) {
            address participantAddr = drop.participantAddresses[i];
            addresses[i] = participantAddr;
            names[i] = drop.participantNames[participantAddr];
        }
        
        return (addresses, names);
    }
    
    /**
     * @dev Get drop information
     * @param dropId The ID of the drop
     * @return host The host address
     * @return entryFee The entry fee
     * @return rewardAmount The total reward
     * @return maxParticipants Maximum number of participants
     * @return currentParticipants Current number of participants
     * @return isActive Whether the drop is active
     * @return isCompleted Whether the drop is completed
     * @return isPaidEntry Whether participants pay
     * @return numWinners Number of winners
     * @return winners Array of winner addresses
     */
    function getDropInfo(uint256 dropId) external view returns (
        address host,
        uint256 entryFee,
        uint256 rewardAmount,
        uint256 maxParticipants,
        uint256 currentParticipants,
        bool isActive,
        bool isCompleted,
        bool isPaidEntry,
        uint32 numWinners,
        address[] memory winners
    ) {
        Drop storage drop = drops[dropId];
        
        return (
            drop.host,
            drop.entryFee,
            drop.rewardAmount,
            drop.maxParticipants,
            drop.currentParticipants,
            drop.isActive,
            drop.isCompleted,
            drop.isPaidEntry,
            drop.numWinners,
            drop.winners
        );
    }
    
    /**
     * @dev Check if an address has joined a drop
     * @param dropId The ID of the drop
     * @param participant The address to check
     * @return hasJoined Whether the address has joined
     */
    function hasJoinedDrop(uint256 dropId, address participant) external view returns (bool hasJoined) {
        return drops[dropId].participants[participant];
    }
    
    /**
     * @dev Cancel a drop and return funds to participants or host (host or owner only)
     * @param dropId The ID of the drop to cancel
     */
    function cancelDrop(uint256 dropId) external nonReentrant {
        Drop storage drop = drops[dropId];
        
        require(msg.sender == drop.host || msg.sender == owner(), "Only host or owner can cancel");
        require(drop.isActive, "Drop is not active");
        require(!drop.isCompleted, "Drop is already completed");
        
        // Mark as not active and completed
        drop.isActive = false;
        drop.isCompleted = true;
        
        // Return funds
        if (drop.isPaidEntry) {
            // Refund participants
            for (uint256 i = 0; i < drop.currentParticipants; i++) {
                address participant = drop.participantAddresses[i];
                (bool success, ) = participant.call{value: drop.entryFee}("");
                require(success, "Refund failed");
            }
        } else {
            // Refund host
            (bool success, ) = drop.host.call{value: drop.rewardAmount}("");
            require(success, "Host refund failed");
        }
    }
    
    /**
     * @dev Withdraw LINK tokens from the contract
     */
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }
    
    /**
     * @dev Withdraw native ETH from the contract
     * @param amount The amount to withdraw in wei
     */
    function withdrawNative(uint256 amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
    fallback() external payable {}
}