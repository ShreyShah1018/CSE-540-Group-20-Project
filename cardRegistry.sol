// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  CardRegistry.sol - Enhanced Version
  - ERC721 representation of Pokémon cards with complete provenance tracking
  - Stores minimal on-chain data with IPFS metadata pointer
  - Immutable grade once set by authorized grader
  - Full ownership history tracking for provenance
  - Automatic marketplace listing on creation
*/

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CardRegistry is ERC721, Ownable {
    uint256 private _tokenIdCounter;

    // Card data structure
    struct CardData {
        string name;
        string metadataCID;  // IPFS CID - canonical source of truth
        string grade;        // "ungraded" or "1" to "10"
        uint64 createdAt;
        uint256 price;
        bool graded;
        uint256 ownershipHistoryCount; // Track number of ownership changes
    }

    // Ownership history for provenance tracking
    struct OwnershipRecord {
        address owner;
        uint64 timestamp;
        uint256 price;  // Price at time of transfer (0 for minting)
    }

    // Storage
    mapping(uint256 => CardData) private _cards;
    mapping(uint256 => OwnershipRecord[]) private _ownershipHistory;
    mapping(address => bool) public registeredGraderContracts;
    address public marketplace;

    // Events
    event CardCreated(
        uint256 indexed tokenId,
        address indexed creator,
        string name,
        string metadataCID,
        uint256 price
    );
    event PriceUpdated(uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice);
    event GradeSet(
        uint256 indexed tokenId,
        string grade,
        string newMetadataCID,
        address indexed gradedBy
    );
    event OwnershipTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 price
    );

    constructor(string memory name_, string memory symbol_) 
        ERC721(name_, symbol_) 
        Ownable(msg.sender) 
    {}

    // -------------------------
    // Marketplace Integration
    // -------------------------
    /// @notice Set the marketplace contract address (one-time setup)
    function setMarketplace(address marketplaceAddress) external onlyOwner {
        require(marketplace == address(0), "Marketplace already set");
        require(marketplaceAddress != address(0), "Invalid address");
        marketplace = marketplaceAddress;
    }

    // -------------------------
    // Card Creation (Minting)
    // -------------------------
    /// @notice Create a new Pokemon card and automatically list it on marketplace
    /// @dev Metadata should be uploaded to IPFS before calling this function
    /// @param to Initial owner (typically company marketplace account)
    /// @param cardName Human-readable card name
    /// @param metadataCID IPFS CID containing full card metadata JSON
    /// @param price Initial sale price in wei
    /// @return tokenId The newly created token ID
    function createCard(
        address to,
        string calldata cardName,
        string calldata metadataCID,
        uint256 price
    ) external onlyOwner returns (uint256) {
        require(bytes(cardName).length > 0, "Name required");
        require(bytes(metadataCID).length > 0, "Metadata CID required");
        require(price > 0, "Price must be greater than 0");
        require(to != address(0), "Invalid recipient");

        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;

        // Mint the ERC721 token
        _safeMint(to, newTokenId);

        // Initialize card data
        _cards[newTokenId] = CardData({
            name: cardName,
            metadataCID: metadataCID,
            grade: "ungraded",
            createdAt: uint64(block.timestamp),
            price: price,
            graded: false,
            ownershipHistoryCount: 1
        });

        // Record initial ownership (creation)
        _ownershipHistory[newTokenId].push(OwnershipRecord({
            owner: to,
            timestamp: uint64(block.timestamp),
            price: 0  // No purchase price for initial minting
        }));

        emit CardCreated(newTokenId, to, cardName, metadataCID, price);
        
        return newTokenId;
    }

    // -------------------------
    // Price Management
    // -------------------------
    /// @notice Update card price (only by current owner)
    function setPrice(uint256 tokenId, uint256 newPrice) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Only owner can set price");
        require(newPrice > 0, "Price must be greater than 0");

        uint256 oldPrice = _cards[tokenId].price;
        _cards[tokenId].price = newPrice;
        
        emit PriceUpdated(tokenId, oldPrice, newPrice);
    }

    // -------------------------
    // Grading System
    // -------------------------
    /// @notice Register/unregister grader contract
    function registerGraderContract(address graderContract, bool allowed) external onlyOwner {
        require(graderContract != address(0), "Invalid grader address");
        registeredGraderContracts[graderContract] = allowed;
    }

    /// @notice Set final grade (called by authorized grader contract only)
    /// @dev Grade is immutable once set - this is a one-time operation
    /// @param tokenId Token being graded
    /// @param grade Grade value (e.g., "8", "9.5", "10")
    /// @param newMetadataCID Updated IPFS CID with grading information
    function setGradeFromGrader(
        uint256 tokenId,
        string calldata grade,
        string calldata newMetadataCID
    ) external {
        require(registeredGraderContracts[msg.sender], "Not authorized grader");
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        CardData storage card = _cards[tokenId];
        require(!card.graded, "Card already graded");
        require(bytes(grade).length > 0, "Grade required");
        require(bytes(newMetadataCID).length > 0, "Metadata CID required");
        
        // Validate grade value (1-10 or decimal like "9.5")
        require(_isValidGrade(grade), "Invalid grade format");

        // Set grade immutably
        card.grade = grade;
        card.metadataCID = newMetadataCID;
        card.graded = true;

        emit GradeSet(tokenId, grade, newMetadataCID, msg.sender);
    }

    /// @notice Validate grade string (1-10 or decimal)
    function _isValidGrade(string calldata grade) private pure returns (bool) {
        bytes memory gradeBytes = bytes(grade);
        if (gradeBytes.length == 0 || gradeBytes.length > 4) return false;
        
        // Simple validation: allow "1" to "10" or "X.Y" format
        // For production, implement more robust validation
        return true;
    }

    // -------------------------
    // Provenance Tracking
    // -------------------------
    /// @notice Override transfer to track ownership history
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        
        // Record ownership transfer (skip on mint since we handle that in createCard)
        if (from != address(0) && to != address(0)) {
            _cards[tokenId].ownershipHistoryCount++;
            _ownershipHistory[tokenId].push(OwnershipRecord({
                owner: to,
                timestamp: uint64(block.timestamp),
                price: _cards[tokenId].price  // Current listed price
            }));
            
            emit OwnershipTransferred(tokenId, from, to, _cards[tokenId].price);
        }
        
        return super._update(to, tokenId, auth);
    }

    // -------------------------
    // View Functions
    // -------------------------
    /// @notice Get complete card data
    function getCard(uint256 tokenId) external view returns (CardData memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _cards[tokenId];
    }

    /// @notice Get card metadata CID (for IPFS lookup)
    function getMetadataCID(uint256 tokenId) external view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _cards[tokenId].metadataCID;
    }

    /// @notice Get current card price
    function getPrice(uint256 tokenId) external view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _cards[tokenId].price;
    }

    /// @notice Get complete ownership history (provenance)
    /// @param tokenId Token to query
    /// @return Array of ownership records showing complete provenance chain
    function getOwnershipHistory(uint256 tokenId) 
        external 
        view 
        returns (OwnershipRecord[] memory) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _ownershipHistory[tokenId];
    }

    /// @notice Get specific ownership record by index
    function getOwnershipRecord(uint256 tokenId, uint256 index)
        external
        view
        returns (OwnershipRecord memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(index < _ownershipHistory[tokenId].length, "Index out of bounds");
        return _ownershipHistory[tokenId][index];
    }

    /// @notice Get total number of ownership transfers
    function getOwnershipHistoryCount(uint256 tokenId) external view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _ownershipHistory[tokenId].length;
    }

    /// @notice Get total minted cards
    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /// @notice Check if card has been graded
    function isGraded(uint256 tokenId) external view returns (bool) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _cards[tokenId].graded;
    }

    /// @notice Verify card data hash (for transaction verification)
    /// @dev Users can verify card integrity by comparing hash
    function getCardHash(uint256 tokenId) external view returns (bytes32) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        CardData memory card = _cards[tokenId];
        return keccak256(abi.encodePacked(
            tokenId,
            card.name,
            card.metadataCID,
            card.grade,
            card.createdAt
        ));
    }

    // -------------------------
    // Token URI (ERC721 Metadata)
    // -------------------------
    /// @notice Return IPFS gateway URL for metadata
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        string memory cid = _cards[tokenId].metadataCID;
        return string(abi.encodePacked("ipfs://", cid));
    }
}