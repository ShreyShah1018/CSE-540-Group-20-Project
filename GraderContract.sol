// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  GraderContract.sol
  - Simple FIFO queue of tokenIds waiting for grading.
  - Token owners call enqueueForGrading(tokenId) to request grading.
  - Authorized grader addresses (managed by this contract owner) may call grade(tokenId, grade, newCID)
    which will call back into CardRegistry to set the final grade (CardRegistry must have this GraderContract
    registered via registerGraderContract()).
*/

import "@openzeppelin/contracts/access/Ownable.sol";

interface ICardRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function setGradeFromGrader(uint256 tokenId, string calldata grade, string calldata newMetadataCID) external;
}

contract GraderContract is Ownable {
    ICardRegistry public cardRegistry;

    // Simple queue implemented as array plus head index (FIFO)
    uint256[] private queue;
    uint256 private head;

    // authorized grader EOAs that can finalize grading
    mapping(address => bool) public authorizedGraders;

    event Enqueued(uint256 indexed tokenId, address indexed requester);
    event Graded(uint256 indexed tokenId, string grade, string newCID, address indexed grader);
    event GraderAdded(address indexed grader);
    event GraderRemoved(address indexed grader);

    constructor(address cardRegistryAddress) Ownable(msg.sender) {
        require(cardRegistryAddress != address(0), "Invalid registry");
        cardRegistry = ICardRegistry(cardRegistryAddress);
        head = 0;
    }

    // -----------------------
    // Queue operations
    // -----------------------
    /// @notice Token owner requests grading by adding tokenId to queue
    function enqueueForGrading(uint256 tokenId) external {
        address tokenOwner = cardRegistry.ownerOf(tokenId);
        require(tokenOwner == msg.sender, "Only token owner can request grading");

        queue.push(tokenId);
        emit Enqueued(tokenId, msg.sender);
    }

    /// @notice View next item (does not remove)
    function peek() external view returns (uint256 tokenId, bool exists) {
        if (head < queue.length) {
            return (queue[head], true);
        } else {
            return (0, false);
        }
    }

    /// @notice Pop next item from queue (grader convenience). Caller must be an authorized grader.
    function popNext() external returns (uint256 tokenId) {
        require(authorizedGraders[msg.sender], "Not an authorized grader");
        require(head < queue.length, "Queue empty");

        tokenId = queue[head];
        head++;
        return tokenId;
    }

    // -----------------------
    // Grading operations
    // -----------------------
    function addGrader(address grader, bool allowed) external onlyOwner {
        authorizedGraders[grader] = allowed;
        if (allowed) emit GraderAdded(grader); else emit GraderRemoved(grader);
    }

    /// @notice Grade a token and provide new metadata CID (metadata should be uploaded to IPFS first)
    /// @dev Requires that this contract is registered in CardRegistry as a valid grader contract.
    function grade(uint256 tokenId, string calldata gradeStr, string calldata newMetadataCID) external {
        require(authorizedGraders[msg.sender], "Not an authorized grader");
        // Forward grading to the CardRegistry which enforces immutability of grade
        cardRegistry.setGradeFromGrader(tokenId, gradeStr, newMetadataCID);
        emit Graded(tokenId, gradeStr, newMetadataCID, msg.sender);
    }

    // -----------------------
    // Helpers
    // -----------------------
    function queueLength() external view returns (uint256) {
        // number of items remaining in queue
        return queue.length - head;
    }
}
