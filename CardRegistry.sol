// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  CardRegistry.sol
  - ERC721 representation of Pokémon cards
  - Stores a minimal on-chain record while metadata (images, full JSON)
    is expected to live on IPFS. We store the IPFS CID on-chain as the canonical pointer.
  - Maintains price, metadataCID, grade (immutable once set), and createdAt.
  - Only the contract deployer (company) can mint new cards.
  - A registered Grader contract may set the grade once (immutable after grading).
*/

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract CardRegistry is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    // Card data stored on-chain (lightweight)
    struct CardData {
        string name;         // human-friendly name
        string metadataCID;  // IPFS CID pointing to metadata JSON (kept on IPFS)
        string grade;        // "ungraded" or "1".."10"
        uint64 createdAt;    // timestamp of minting
        uint256 price;       // price in wei (source of truth for marketplace)
        bool graded;         // true if grade has been finalized
    }

    // tokenId => CardData
    mapping(uint256 => CardData) private _cards;

    // Registered grader contracts allowed to call setGradeFromGrader
    mapping(address => bool) public registeredGraderContracts;

    // Events
    event CardCreated(uint256 indexed tokenId, address indexed creator, string metadataCID, uint256 price);
    event PriceUpdated(uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice);
    event GradeSet(uint256 indexed tokenId, string grade, string newMetadataCID, address gradedBy);

    // Constructor: Company deploys contract and becomes owner
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) Ownable(msg.sender) {}

    // -------------------------
    // Minting / Creation
    // -------------------------
    /// @notice Company (contract owner) mints a new card. Metadata should be uploaded to IPFS first.
    /// @param to The initial owner (typically the company marketplace account)
    /// @param cardName Human readable name
    /// @param metadataCID IPFS CID for the card's metadata JSON (canonical pointer)
    /// @param price Starting price in wei
    function createCard(
        address to,
        string calldata cardName,
        string calldata metadataCID,
        uint256 price
    ) external onlyOwner returns (uint256) {
        require(bytes(cardName).length > 0, "Name required");
        require(bytes(metadataCID).length > 0, "CID required");

        _tokenIdCounter.increment();
        uint256 newId = _tokenIdCounter.current();

        // Mint ERC721 token to `to`
        _safeMint(to, newId);

        // Optional: set tokenURI to metadataCID (if you prefer), but we store CID separately
        _setTokenURI(newId, metadataCID);

        // Initialize CardData: grade = "ungraded"
        _cards[newId] = CardData({
            name: cardName,
            metadataCID: metadataCID,
            grade: "ungraded",
            createdAt: uint64(block.timestamp),
            price: price,
            graded: false
        });

        emit CardCreated(newId, to, metadataCID, price);
        return newId;
    }

    // -------------------------
    // Read helpers
    // -------------------------
    function getCard(uint256 tokenId) external view returns (CardData memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _cards[tokenId];
    }

    function getMetadataCID(uint256 tokenId) external view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _cards[tokenId].metadataCID;
    }

    function getPrice(uint256 tokenId) external view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _cards[tokenId].price;
    }

    // -------------------------
    // Price management (only token owner)
    // -------------------------
    /// @notice Only the current owner of the token may update its price.
    function setPrice(uint256 tokenId, uint256 newPrice) external {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner, "Only token owner can change price");

        uint256 old = _cards[tokenId].price;
        _cards[tokenId].price = newPrice;
        emit PriceUpdated(tokenId, old, newPrice);
    }

    // -------------------------
    // Grading integration
    // -------------------------
    /// @notice Owner registers/unregisters allowed grader contract addresses
    function registerGraderContract(address graderContract, bool allowed) external onlyOwner {
        registeredGraderContracts[graderContract] = allowed;
    }

    /// @notice Called only by an authorized GraderContract to set a final grade.
    ///        This operation is irreversible for `grade` (once set, graded == true).
    /// @param tokenId Token being graded
    /// @param grade Numeric/text grade (e.g., "8" or "9.5"), must be non-empty
    /// @param newMetadataCID New metadata CID that includes grade in metadata JSON
    function setGradeFromGrader(uint256 tokenId, string calldata grade, string calldata newMetadataCID) external {
        require(registeredGraderContracts[msg.sender], "Caller not registered grader");
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        CardData storage c = _cards[tokenId];

        require(!c.graded, "Card already graded");
        require(bytes(grade).length > 0, "Grade required");
        require(bytes(newMetadataCID).length > 0, "New CID required");

        c.grade = grade;
        c.metadataCID = newMetadataCID; // update on-chain pointer to newly graded metadata
        c.graded = true;

        // update tokenURI as well for wallets/marketplaces that use it
        _setTokenURI(tokenId, newMetadataCID);

        emit GradeSet(tokenId, grade, newMetadataCID, msg.sender);
    }

    // -------------------------
    // Internal transfer hook (provenance note)
    // -------------------------
    // If you want to implement provenance logs, override transfer hooks here.
    // For simplicity in this demo, provenance is visible from transfer events and registry ownerOf history.
    // OpenZeppelin v5 uses _update hook; we will call super._update and not modify behavior here.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    // -------------------------
    // Helpers
    // -------------------------
    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter.current();
    }
}
