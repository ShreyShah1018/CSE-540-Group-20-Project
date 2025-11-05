### Pokémon Card Verification – Group 23 ###

Course: CSE-540 (Blockchain Systems)
Network: Polygon Amoy Testnet

### Description of the Project ###

This project demonstrates how blockchain technology can be applied to the verification of collectible Pokémon cards.
Each card’s essential details—such as its name, card number, and assigned grade—are stored immutably on the blockchain.

The current implementation focuses on the core verification mechanism:

Users can upload Pokémon card details. The contract owner (main verifier) can review and assign a grade to mark authenticity. All records are transparent and permanently stored on the Polygon Amoy Testnet, providing a foundation for future extensions such as NFT minting, marketplaces, and multi-verifier roles.

### Dependencies / Setup Instructions ###

Remix IDE or a local Solidity environment (≥ 0.8.24).

MetaMask Wallet connected to Polygon Amoy Testnet.

Test POL tokens available from official Polygon Faucet.

### Deployment ###
1) Connect your metamask wallet with Polygon Amoy Testnet.
2) Compile the contract in the github file.
3) You can either deploy the contract and have owner/verifier access or you can use the following address (contract deployed by us) to test user side. Once info of the card is uploaded it can only be verified by the person who has deployed the contract.

Contract Address: 0x697Fd861cB9E19363Aa3ef24DF5BDbFb5359195e
