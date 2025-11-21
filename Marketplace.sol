// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Marketplace.sol
  - Lightweight marketplace that uses CardRegistry as the source of truth for price and metadata CID.
  - Cards remain "listed" indefinitely after creation unless the owner explicitly unlists (optional).
  - Buyers must pass the expected CID when buying to verify the item they expect matches the on-chain CID.
  - Sellers (current owner) must approve this marketplace contract to transfer their token.
*/

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ICardRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getPrice(uint256 tokenId) external view returns (uint256);
    function getMetadataCID(uint256 tokenId) external view returns (string memory);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract Marketplace is ReentrancyGuard {
    IERC721 public cardToken; // actual ERC721 token interface
    ICardRegistry public cardRegistry; // registry (for reading price and CID)

    // Listing status: a token is listed if listed[tokenId] == true
    mapping(uint256 => bool) public listed;

    event Listed(uint256 indexed tokenId);
    event Unlisted(uint256 indexed tokenId);
    event CardBought(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price);

    constructor(address cardRegistryAddress) {
        require(cardRegistryAddress != address(0), "Invalid registry");
        cardRegistry = ICardRegistry(cardRegistryAddress);
        cardToken = IERC721(cardRegistryAddress); // works because registry is also ERC721
    }

    /// @notice Company or owner lists a token (optional; creation could automatically list)
    function list(uint256 tokenId) external {
        address tokenOwner = cardRegistry.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "Only owner can list");
        listed[tokenId] = true;
        emit Listed(tokenId);
    }

    /// @notice Owner may unlist if they want it removed from marketplace
    function unlist(uint256 tokenId) external {
        address tokenOwner = cardRegistry.ownerOf(tokenId);
        require(msg.sender == tokenOwner, "Only owner can unlist");
        listed[tokenId] = false;
        emit Unlisted(tokenId);
    }

    /// @notice Buy a listed token. Buyer must provide exact price in msg.value.
    /// @param tokenId The token to buy
    /// @param expectedCID The IPFS CID buyer expects for this token (defensive check)
    function buy(uint256 tokenId, string calldata expectedCID) external payable nonReentrant {
        require(listed[tokenId], "Token not listed");
        uint256 price = cardRegistry.getPrice(tokenId);
        require(price > 0, "Token not for sale");
        require(msg.value == price, "Incorrect payment amount");

        // Defensive check: ensure the buyer expects the same CID
        string memory actualCID = cardRegistry.getMetadataCID(tokenId);
        require(keccak256(bytes(actualCID)) == keccak256(bytes(expectedCID)), "CID mismatch");

        address seller = cardRegistry.ownerOf(tokenId);
        require(seller != address(0), "Invalid seller");
        require(seller != msg.sender, "Buyer cannot be seller");

        // Transfer token from seller -> buyer. Seller must have approved marketplace beforehand.
        cardRegistry.safeTransferFrom(seller, msg.sender, tokenId);

        // Forward funds to seller (simple, no fees)
        (bool sent, ) = payable(seller).call{value: msg.value}("");
        require(sent, "Failed to send funds");

        // Listing remains active (per project requirement). Ownership changed.
        emit CardBought(tokenId, msg.sender, seller, msg.value);
    }

    /// @notice Helper to check if a token is listed and its price
    function isListed(uint256 tokenId) external view returns (bool, uint256) {
        return (listed[tokenId], cardRegistry.getPrice(tokenId));
    }
}
