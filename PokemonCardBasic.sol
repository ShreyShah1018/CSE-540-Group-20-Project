// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract PokemonCardBasic {
    // Deployer/Owner == can verify cards
    address public owner;
    constructor() {
        owner = msg.sender; // For now only deployer can verify the cards 
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can verify");
        _;
    }

    // Structure of the card
    enum Status { Pending, Verified } 

    struct Card {
        address submitter;   // address of the user who uploads the cards
        string name;         // pokemon name
        string number;       // card number from the respective set
        Status status;       // Flag for the card indicating whether it is verified or pending
        string grade;        // grade for the card's quality from 1 to 10
        uint64 submittedAt;  // timestamp created during submission
        uint64 verifiedAt;   // when the card is verified
    }

    uint256 public nextId;
    mapping(uint256 => Card) public cards;

    // Events for the cards
    event CardSubmitted(uint256 indexed cardId, address indexed submitter, string name, string number);
    event CardVerified(uint256 indexed cardId, string grade);

    // User == can submit cards but cannot verify or grade them
    function submitCard(string calldata name, string calldata number) external returns (uint256 cardId) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(number).length > 0, "Number required");

        cardId = ++nextId;
        cards[cardId] = Card({
            submitter: msg.sender,
            name: name,
            number: number,
            status: Status.Pending,
            grade: "",
            submittedAt: uint64(block.timestamp),
            verifiedAt: 0
        });

        emit CardSubmitted(cardId, msg.sender, name, number);
    }

    // Function of card verification and grading = is only allowed to be used by the owner/deployer
    function verifyAndGrade(uint256 cardId, string calldata grade) external onlyOwner {
        Card storage c = cards[cardId];
        require(c.submitter != address(0), "Card not found");
        require(c.status == Status.Pending, "Already verified");
        require(bytes(grade).length > 0, "Grade required");

        c.status = Status.Verified;
        c.grade = grade;
        c.verifiedAt = uint64(block.timestamp);

        emit CardVerified(cardId, grade);
    }

    // This functions allow user/deployer/owner to view cards based on their IDs and also indicate verification status
    function getCard(uint256 cardId) external view returns (Card memory) {
        return cards[cardId];
    }

    function isVerified(uint256 cardId) external view returns (bool) {
        return cards[cardId].status == Status.Verified;
    }
}