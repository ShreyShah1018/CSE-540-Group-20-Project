// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  GraderContract.sol - Enhanced Version
  - FIFO queue for grading requests with improved tracking
  - Prevents duplicate grading requests for same token
  - Tracks grading status and completion
  - Fee-based grading system (optional)
  - Emergency withdrawal functions
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ICardRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function setGradeFromGrader(
        uint256 tokenId,
        string calldata grade,
        string calldata newMetadataCID
    ) external;
    function isGraded(uint256 tokenId) external view returns (bool);
}

contract GraderContract is Ownable, ReentrancyGuard {
    ICardRegistry public cardRegistry;

    // Queue implementation
    uint256[] private queue;
    uint256 private head;

    // Grading fee (optional, can be 0)
    uint256 public gradingFee;

    // Authorized graders
    mapping(address => bool) public authorizedGraders;

    // Track tokens in queue to prevent duplicates
    mapping(uint256 => bool) private inQueue;

    // Track grading requests and completion
    struct GradingRequest {
        address requester;
        uint64 requestTime;
        bool completed;
        string finalGrade;
    }
    mapping(uint256 => GradingRequest) public gradingRequests;

    // Events
    event Enqueued(
        uint256 indexed tokenId,
        address indexed requester,
        uint256 queuePosition
    );
    event Graded(
        uint256 indexed tokenId,
        string grade,
        string newCID,
        address indexed grader
    );
    event GraderAdded(address indexed grader);
    event GraderRemoved(address indexed grader);
    event GradingFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeWithdrawn(address indexed recipient, uint256 amount);

    constructor(address cardRegistryAddress) Ownable(msg.sender) {
        require(cardRegistryAddress != address(0), "Invalid registry address");
        cardRegistry = ICardRegistry(cardRegistryAddress);
        head = 0;
        gradingFee = 0; // Can be updated by owner
    }

    // -------------------------
    // Fee Management
    // -------------------------
    /// @notice Update grading fee (only owner)
    function setGradingFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = gradingFee;
        gradingFee = newFee;
        emit GradingFeeUpdated(oldFee, newFee);
    }

    /// @notice Withdraw accumulated fees
    function withdrawFees(
        address payable recipient
    ) external onlyOwner nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");

        (bool success, ) = recipient.call{value: balance}("");
        require(success, "Withdrawal failed");

        emit FeeWithdrawn(recipient, balance);
    }

    // -------------------------
    // Queue Operations
    // -------------------------
    /// @notice Request grading for a token (must be token owner)
    function enqueueForGrading(uint256 tokenId) external payable {
        address tokenOwner = cardRegistry.ownerOf(tokenId);
        require(
            tokenOwner == msg.sender,
            "Only token owner can request grading"
        );
        require(!inQueue[tokenId], "Token already in queue");
        require(!cardRegistry.isGraded(tokenId), "Token already graded");
        require(msg.value >= gradingFee, "Insufficient grading fee");

        // Refund excess payment
        if (msg.value > gradingFee) {
            (bool refunded, ) = payable(msg.sender).call{
                value: msg.value - gradingFee
            }("");
            require(refunded, "Refund failed");
        }

        // Add to queue
        queue.push(tokenId);
        inQueue[tokenId] = true;

        // Record request
        gradingRequests[tokenId] = GradingRequest({
            requester: msg.sender,
            requestTime: uint64(block.timestamp),
            completed: false,
            finalGrade: ""
        });

        emit Enqueued(tokenId, msg.sender, queue.length - 1);
    }

    /// @notice View next token in queue without removing
    function peek() external view returns (uint256 tokenId, bool exists) {
        if (head < queue.length) {
            return (queue[head], true);
        }
        return (0, false);
    }

    /// @notice Pop next token from queue (authorized graders only)
    function popNext() external returns (uint256 tokenId) {
        require(authorizedGraders[msg.sender], "Not authorized grader");
        require(head < queue.length, "Queue empty");

        tokenId = queue[head];
        head++;
        inQueue[tokenId] = false;

        return tokenId;
    }

    /// @notice View all pending tokens in queue
    function getPendingQueue() external view returns (uint256[] memory) {
        uint256 remaining = queue.length - head;
        uint256[] memory pending = new uint256[](remaining);

        for (uint256 i = 0; i < remaining; i++) {
            pending[i] = queue[head + i];
        }

        return pending;
    }

    /// @notice Check if token is currently in queue
    function isInQueue(uint256 tokenId) external view returns (bool) {
        return inQueue[tokenId];
    }

    // -------------------------
    // Grader Management
    // -------------------------
    /// @notice Add or remove authorized grader
    function setGrader(address grader, bool allowed) external onlyOwner {
        require(grader != address(0), "Invalid grader address");
        authorizedGraders[grader] = allowed;

        if (allowed) {
            emit GraderAdded(grader);
        } else {
            emit GraderRemoved(grader);
        }
    }

    /// @notice Add multiple graders at once
    function addGradersBatch(address[] calldata graders) external onlyOwner {
        for (uint256 i = 0; i < graders.length; i++) {
            require(graders[i] != address(0), "Invalid grader address");
            authorizedGraders[graders[i]] = true;
            emit GraderAdded(graders[i]);
        }
    }

    // -------------------------
    // Grading Operations
    // -------------------------
    /// @notice Grade a token with new metadata CID
    /// @dev Metadata with grade info should be uploaded to IPFS before calling
    /// @param tokenId Token to grade
    /// @param gradeStr Grade value (1-10)
    /// @param newMetadataCID Updated IPFS CID with grading information
    function grade(
        uint256 tokenId,
        string calldata gradeStr,
        string calldata newMetadataCID
    ) external nonReentrant {
        require(authorizedGraders[msg.sender], "Not authorized grader");
        require(bytes(gradeStr).length > 0, "Grade required");
        require(bytes(newMetadataCID).length > 0, "Metadata CID required");

        GradingRequest storage request = gradingRequests[tokenId];
        require(request.requester != address(0), "No grading request found");
        require(!request.completed, "Already graded");

        // Call CardRegistry to set grade
        cardRegistry.setGradeFromGrader(tokenId, gradeStr, newMetadataCID);

        // Mark as completed
        request.completed = true;
        request.finalGrade = gradeStr;

        // If this token is currently at head, advance queue
        if (head < queue.length && queue[head] == tokenId) {
            head++;
            inQueue[tokenId] = false;
        } else {
            // Optional: if you want to prevent grading out-of-order,
            // uncomment the following line instead of the if-block above:
            // revert("Can only grade token at queue head");
        }

        emit Graded(tokenId, gradeStr, newMetadataCID, msg.sender);
    }

    // -------------------------
    // View Functions
    // -------------------------
    /// @notice Get number of tokens waiting in queue
    function queueLength() external view returns (uint256) {
        return queue.length > head ? queue.length - head : 0;
    }

    /// @notice Get total grading requests processed
    function totalProcessed() external view returns (uint256) {
        return head;
    }

    /// @notice Get grading request details
    function getGradingRequest(
        uint256 tokenId
    )
        external
        view
        returns (
            address requester,
            uint64 requestTime,
            bool completed,
            string memory finalGrade
        )
    {
        GradingRequest memory request = gradingRequests[tokenId];
        return (
            request.requester,
            request.requestTime,
            request.completed,
            request.finalGrade
        );
    }

    /// @notice Get contract balance (accumulated fees)
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // -------------------------
    // Emergency Functions
    // -------------------------
    /// @notice Clear queue in case of issues (owner only)
    function emergencyClearQueue() external onlyOwner {
        // Mark all tokens as not in queue
        for (uint256 i = head; i < queue.length; i++) {
            inQueue[queue[i]] = false;
        }

        // Reset queue
        delete queue;
        head = 0;
    }

    /// @notice Receive function for accepting fees
    receive() external payable {}
}
