// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Marketplace.sol - Enhanced Version
  - Secure marketplace with CID verification on purchases
  - Cards automatically listed after creation
  - Optional platform fee system
  - Purchase history tracking
  - Emergency pause functionality
*/

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ICardRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getPrice(uint256 tokenId) external view returns (uint256);
    function getMetadataCID(uint256 tokenId) external view returns (string memory);
    function getCardHash(uint256 tokenId) external view returns (bytes32);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract Marketplace is ReentrancyGuard, Pausable, Ownable {
    IERC721 public cardToken;
    ICardRegistry public cardRegistry;

    // Platform fee (in basis points, e.g., 250 = 2.5%)
    uint256 public platformFeeBps;
    address public feeRecipient;

    // Listing management
    mapping(uint256 => bool) public listed;
    
    // Purchase history for analytics
    struct Purchase {
        address buyer;
        address seller;
        uint256 price;
        uint64 timestamp;
    }
    mapping(uint256 => Purchase[]) private purchaseHistory;

    // Events
    event Listed(uint256 indexed tokenId, address indexed owner, uint256 price);
    event Unlisted(uint256 indexed tokenId, address indexed owner);
    event CardPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 platformFee
    );
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    constructor(address cardRegistryAddress) Ownable(msg.sender) {
        require(cardRegistryAddress != address(0), "Invalid registry address");
        cardRegistry = ICardRegistry(cardRegistryAddress);
        cardToken = IERC721(cardRegistryAddress);
        platformFeeBps = 250; // 2.5% default fee
        feeRecipient = msg.sender;
    }

    // -------------------------
    // Platform Configuration
    // -------------------------
    /// @notice Update platform fee (max 10%)
    function setPlatformFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "Fee too high (max 10%)");
        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    /// @notice Update fee recipient address
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /// @notice Pause/unpause marketplace (emergency only)
    function setPaused(bool paused) external onlyOwner {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    // -------------------------
    // Listing Management
    // -------------------------
    /// @notice List a token for sale (owner only)
    function list(uint256 tokenId) external {
        address tokenOwner = cardRegistry.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "Only owner can list");
        require(!listed[tokenId], "Already listed");
        
        uint256 price = cardRegistry.getPrice(tokenId);
        require(price > 0, "Price must be set");

        listed[tokenId] = true;
        emit Listed(tokenId, msg.sender, price);
    }

    /// @notice Unlist a token (owner only)
    function unlist(uint256 tokenId) external {
        address tokenOwner = cardRegistry.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "Only owner can unlist");
        require(listed[tokenId], "Not listed");

        listed[tokenId] = false;
        emit Unlisted(tokenId, msg.sender);
    }

    /// @notice Auto-list tokens when created (called by CardRegistry or owner)
    function autoList(uint256 tokenId) external {
        address tokenOwner = cardRegistry.ownerOf(tokenId);
        require(
            msg.sender == tokenOwner || msg.sender == address(cardRegistry),
            "Unauthorized"
        );
        
        listed[tokenId] = true;
        uint256 price = cardRegistry.getPrice(tokenId);
        emit Listed(tokenId, tokenOwner, price);
    }

    // -------------------------
    // Purchase Functions
    // -------------------------
    /// @notice Purchase a listed card with CID verification
    /// @param tokenId Token to purchase
    /// @param expectedCID Expected IPFS CID (security check)
    function buy(uint256 tokenId, string calldata expectedCID) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        require(listed[tokenId], "Token not listed");
        
        // Get current price and verify payment
        uint256 price = cardRegistry.getPrice(tokenId);
        require(price > 0, "Token not for sale");
        require(msg.value == price, "Incorrect payment amount");

        // Security: Verify metadata CID matches expectation
        string memory actualCID = cardRegistry.getMetadataCID(tokenId);
        require(
            keccak256(bytes(actualCID)) == keccak256(bytes(expectedCID)),
            "CID mismatch - card may have changed"
        );

        // Get seller and validate
        address seller = cardRegistry.ownerOf(tokenId);
        require(seller != address(0), "Invalid seller");
        require(seller != msg.sender, "Cannot buy your own card");

        // Calculate platform fee
        uint256 platformFee = (price * platformFeeBps) / 10000;
        uint256 sellerAmount = price - platformFee;

        // Transfer token from seller to buyer
        // Seller must have approved this marketplace contract
        cardToken.safeTransferFrom(seller, msg.sender, tokenId);

        // Distribute funds
        if (platformFee > 0) {
            (bool feeSent, ) = payable(feeRecipient).call{value: platformFee}("");
            require(feeSent, "Platform fee transfer failed");
        }

        (bool sellerPaid, ) = payable(seller).call{value: sellerAmount}("");
        require(sellerPaid, "Seller payment failed");

        // Record purchase history
        purchaseHistory[tokenId].push(Purchase({
            buyer: msg.sender,
            seller: seller,
            price: price,
            timestamp: uint64(block.timestamp)
        }));

        // Keep token listed (per requirements - ownership changes, listing remains)
        emit CardPurchased(tokenId, msg.sender, seller, price, platformFee);
    }

    /// @notice Purchase with additional hash verification
    /// @param tokenId Token to purchase
    /// @param expectedCID Expected IPFS CID
    /// @param expectedHash Expected card data hash
    function buyWithHashVerification(
        uint256 tokenId,
        string calldata expectedCID,
        bytes32 expectedHash
    ) external payable nonReentrant whenNotPaused {
        // First verify hash
        bytes32 actualHash = cardRegistry.getCardHash(tokenId);
        require(actualHash == expectedHash, "Card hash mismatch");

        // Then proceed with normal purchase
        this.buy{value: msg.value}(tokenId, expectedCID);
    }

    // -------------------------
    // View Functions
    // -------------------------
    /// @notice Check if token is listed and get details
    function getListingInfo(uint256 tokenId) 
        external 
        view 
        returns (
            bool isListed,
            uint256 price,
            address owner,
            string memory metadataCID
        ) 
    {
        isListed = listed[tokenId];
        price = cardRegistry.getPrice(tokenId);
        owner = cardRegistry.ownerOf(tokenId);
        metadataCID = cardRegistry.getMetadataCID(tokenId);
    }

    /// @notice Get purchase history for a token
    function getPurchaseHistory(uint256 tokenId) 
        external 
        view 
        returns (Purchase[] memory) 
    {
        return purchaseHistory[tokenId];
    }

    /// @notice Get number of times a token has been sold
    function getPurchaseCount(uint256 tokenId) external view returns (uint256) {
        return purchaseHistory[tokenId].length;
    }

    /// @notice Get all currently listed tokens (expensive, use carefully)
    /// @dev This function can be gas-intensive for large token counts
    function getAllListedTokens(uint256 maxTokenId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256 count = 0;
        
        // First pass: count listed tokens
        for (uint256 i = 1; i <= maxTokenId; i++) {
            if (listed[i]) {
                count++;
            }
        }

        // Second pass: populate array
        uint256[] memory listedTokens = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= maxTokenId; i++) {
            if (listed[i]) {
                listedTokens[index] = i;
                index++;
            }
        }

        return listedTokens;
    }

    /// @notice Calculate platform fee for a given price
    function calculatePlatformFee(uint256 price) external view returns (uint256) {
        return (price * platformFeeBps) / 10000;
    }

    // -------------------------
    // Emergency Functions
    // -------------------------
    /// @notice Withdraw stuck ETH (emergency only)
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
}