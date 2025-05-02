// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol"; // Ensure this path is correct
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

/**
 * @title FireballDrop
 * @dev A smart contract for managing drop auctions with Chainlink VRF v2.5 Direct Funding, allowing host-funded or participant-paid rewards
 */
contract FireballDrop is Ownable, ReentrancyGuard, VRFV2PlusWrapperConsumerBase {
    // Chainlink VRF constants
    address public immutable linkAddress; // LINK token address
    uint32 public immutable callbackGasLimit;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant MAX_NUM_WORDS = 3; // Max winners supported

    // Platform fee percentage (in basis points, 100 = 1%)
    uint16 public platformFeePercent;
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
        bool isManualSelection; // True for manual winner selection, false for automatic
        uint32 numWinners; // 1, 2, or 3 winners
        address[] winners; // Array of winner addresses
        mapping(address => bool) participants;
        mapping(uint256 => address) participantAddresses;
        mapping(address => string) participantNames;
    }
    
    // Mapping to store drops
    mapping(uint256 => Drop) public drops;
    uint256 public dropCounter;
    
    // VRF request tracking
    mapping(uint256 => uint256) private s_requestIdToDropId; // Request ID to Drop ID
    mapping(uint256 => bool) private s_requestFulfilled; // Request ID to fulfillment status
    mapping(uint256 => uint256[]) private s_dropToRequestIds; // Drop ID to list of request IDs
    
    // Events
    event DropCreated(
        uint256 indexed dropId,
        address indexed host,
        uint256 entryFee,
        uint256 rewardAmount,
        uint256 maxParticipants,
        bool isPaidEntry,
        bool isManualSelection,
        uint32 numWinners
    );
    event ParticipantJoined(uint256 indexed dropId, address indexed participant, string name, uint256 currentParticipants, uint256 maxParticipants);
    event RequestSent(uint256 indexed requestId, uint256 indexed dropId, uint32 numWinners, bool isManualSelection);
    event RequestFulfilled(uint256 indexed requestId, uint256 indexed dropId, uint256[] randomWords, uint256 payment);
    event WinnersSelected(uint256 indexed dropId, address[] winners, uint256[] prizeAmounts, uint256 platformFee);
    event DropCancelled(uint256 indexed dropId, address indexed host, bool isPaidEntry, uint256 refundedAmount);
    event PlatformFeeUpdated(uint16 newFeePercent);
    
    /**
     * @dev Constructor
     * @param _wrapperAddress address of the VRF v2.5 Wrapper
     * @param _linkAddress address of the LINK token
     * @param _callbackGasLimit gas limit for the VRF callback
     * @param _platformFeePercent initial platform fee percentage in basis points
     * @param _feeReceiver address to receive platform fees
     */
    constructor(
        address _wrapperAddress,
        address _linkAddress,
        uint32 _callbackGasLimit,
        uint16 _platformFeePercent,
        address _feeReceiver
    ) VRFV2PlusWrapperConsumerBase(_wrapperAddress) Ownable(msg.sender) {
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
     * @param isManualSelection True for manual winner selection, false for automatic
     * @param numWinners Number of winners (1, 2, or 3)
     */
    function createDrop(
        uint256 entryFee,
        uint256 rewardAmount,
        uint256 maxParticipants,
        bool isPaidEntry,
        bool isManualSelection,
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
        newDrop.isManualSelection = isManualSelection;
        newDrop.numWinners = numWinners;
        newDrop.winners = new address[](numWinners);
        
        emit DropCreated(
            dropId,
            msg.sender,
            entryFee,
            rewardAmount,
            maxParticipants,
            isPaidEntry,
            isManualSelection,
            numWinners
        );
        
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
        
        emit ParticipantJoined(dropId, msg.sender, name, drop.currentParticipants, drop.maxParticipants);
        
        // Auto-select winners when drop is full (only for automatic selection)
        if (!drop.isManualSelection && drop.currentParticipants == drop.maxParticipants) {
            requestRandomWinners(dropId);
        }
    }
    
    /**
     * @dev Initiate manual winner selection for a drop (host-only)
     * @param dropId The ID of the drop
     */
    function selectWinnersManually(uint256 dropId) external {
        Drop storage drop = drops[dropId];
        
        require(msg.sender == drop.host, "Only host can select winners manually");
        require(drop.isManualSelection, "Drop is not set for manual selection");
        require(drop.isActive, "Drop is not active");
        require(!drop.isCompleted, "Drop is already completed");
        require(drop.currentParticipants >= drop.numWinners, "Not enough participants");
        
        requestRandomWinners(dropId);
    }
    
    /**
     * @dev Internal function to request random numbers for winner selection
     * @param dropId The ID of the drop
     */
    function requestRandomWinners(uint256 dropId) internal {
        Drop storage drop = drops[dropId];
        
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
        s_requestFulfilled[requestId] = false;
        s_dropToRequestIds[dropId].push(requestId);
        emit RequestSent(requestId, dropId, drop.numWinners, drop.isManualSelection);
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
        require(!s_requestFulfilled[_requestId], "Request already fulfilled");
        
        // Select winners using random numbers
        for (uint32 i = 0; i < drop.numWinners; i++) {
            uint256 winnerIndex = _randomWords[i] % drop.currentParticipants;
            drop.winners[i] = drop.participantAddresses[winnerIndex];
        }
        
        // Calculate platform fee and prize distribution
        uint256 platformFee = (drop.rewardAmount * platformFeePercent) / 10000;
        uint256 totalPrize = drop.rewardAmount - platformFee;
        
        // Distribute prizes based on number of winners
        uint256[] memory prizeAmounts = new uint256[](drop.numWinners);
        if (drop.numWinners == 1) {
            prizeAmounts[0] = totalPrize; // 100% to 1st
        } else if (drop.numWinners == 2) {
            prizeAmounts[0] = (totalPrize * 60) / 100; // 60% to 1st
            prizeAmounts[1] = (totalPrize * 40) / 100; // 40% to 2nd
        } else if (drop.numWinners == 3) {
            prizeAmounts[0] = (totalPrize * 50) / 100; // 50% to 1st
            prizeAmounts[1] = (totalPrize * 30) / 100; // 30% to 2nd
            prizeAmounts[2] = (totalPrize * 20) / 100; // 20% to 3rd
        }
        
        // Transfer platform fee
        if (platformFee > 0) {
            (bool feeSuccess, ) = feeReceiver.call{value: platformFee}("");
            require(feeSuccess, "Platform fee transfer failed");
        }
        
        // Transfer prizes to winners
        for (uint32 i = 0; i < drop.numWinners; i++) {
            (bool prizeSuccess, ) = drop.winners[i].call{value: prizeAmounts[i]}("");
            require(prizeSuccess, "Prize transfer failed");
        }
        
        // Mark drop as completed and request as fulfilled
        drop.isCompleted = true;
        s_requestFulfilled[_requestId] = true;
        
        emit RequestFulfilled(_requestId, dropId, _randomWords, platformFee);
        emit WinnersSelected(dropId, drop.winners, prizeAmounts, platformFee);
    }
    
    /**
     * @dev Update the platform fee percentage for future drops
     * @param newFeePercent New platform fee percentage in basis points
     */
    function updatePlatformFee(uint16 newFeePercent) external onlyOwner {
        require(newFeePercent <= 1000, "Fee too high"); // Max 10%
        platformFeePercent = newFeePercent;
        emit PlatformFeeUpdated(newFeePercent);
    }
    
    /**
     * @dev Get VRF request details
     * @param requestId The VRF request ID
     * @return dropId The associated drop ID
     * @return isFulfilled Whether the request is fulfilled
     */
    function getVrfRequestDetails(uint256 requestId) external view returns (uint256 dropId, bool isFulfilled) {
        dropId = s_requestIdToDropId[requestId];
        isFulfilled = s_requestFulfilled[requestId];
        return (dropId, isFulfilled);
    }
    
    /**
     * @dev Get all VRF request IDs for a drop
     * @param dropId The drop ID
     * @return requestIds Array of VRF request IDs
     */
    function getDropVrfRequests(uint256 dropId) external view returns (uint256[] memory requestIds) {
        return s_dropToRequestIds[dropId];
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
     * @return isManualSelection Whether winner selection is manual
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
        bool isManualSelection,
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
            drop.isManualSelection,
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
        uint256 refundedAmount;
        if (drop.isPaidEntry) {
            // Refund participants
            for (uint256 i = 0; i < drop.currentParticipants; i++) {
                address participant = drop.participantAddresses[i];
                (bool success, ) = participant.call{value: drop.entryFee}("");
                require(success, "Refund failed");
                refundedAmount += drop.entryFee;
            }
        } else {
            // Refund host
            (bool success, ) = drop.host.call{value: drop.rewardAmount}("");
            require(success, "Host refund failed");
            refundedAmount = drop.rewardAmount;
        }
        
        emit DropCancelled(dropId, drop.host, drop.isPaidEntry, refundedAmount);
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