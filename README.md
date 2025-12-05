### Provenance Tracking of Pokemon Cards – Group 20 ###

Course: CSE-540 (Blockchain Systems)

### Description of the Project ###

This project demonstrates a decentralized collectible-card system where Pokémon-style cards are created, listed for sale, purchased, graded, and tracked using Ethereum-compatible smart contracts and decentralized IPFS storage.
It implements a full end-to-end Web3 workflow:
- NFT creation (ERC-721)
- Image upload + storage via IPFS
- Marketplace listing & buying
- Grading queue with authorized graders
- Full on-chain provenance
- Multi-page dApp frontend with role-based permissions

### Project Components ###
1. CardRegistry.sol :
   An ERC-721 NFT contract responsible for minting new Pokémon cards, Storing metadata CIDs for IPFS images,Tracking creation date, price, grade, owner and recording the provenance. 
2. Marketplace.sol :
   Provides decentralized buying/selling features
3. GraderContract.sol:
   Implements a professional grading system with a FIFO grading queue. Card owners can “Request Grading” and authorized graders can process and grade these cards.  
4. Frontend (UI) :
   A fully functional multi-page decentralized web app with:
   - Home Page – Account selection + grading queue view
   - Marketplace Page – Only listed cards shown, with images and buy buttons
   - Configuration Page – Enter contract addresses + ABIs (setup)
   - Create Card Page – Owner-only section to mint new cards with IPFS image upload

### Dependencies / Setup Instructions ###

- Remix IDE or a local Solidity environment (0.8.20).
- We have used ganache for local deployment. To install ganache, use command npm install -g ganache. 
- IPFS Desktop to store the card metadata
- To install IPFS Desktop, visit the github page and follow the instructions : https://github.com/ipfs/ipfs-desktop
- Once Installed, you will need to configure IPFS (using ipfs config file )to accept requests from frontend.


### Deployment ###
1) Compile all the contracts
2) In command prompt, type command : ganache --port 8545
3) Connect to the ganache environment in remix IDE by clicking on environment dropdown and selecting custom - HTTP provider
4) Deploy all the smart contracts. The wallet address used to deploy cardregistry.sol will be considered as the owner or the company responsible for card creation. To deploy the other 2 contracts, you will have to paste the deployed cardregistry.sol address in constructor value.
5) In cardregistry, execute fuctions setMarketplace and setApprovalForAll using the marketplace contract address. Execute registerGrader function using the grader address.
6) In grader contract, execute setGrader function with input of an account address that you want to be the grader. You will need to execute the function using the owner's address.
7) Once this is done, you can open the UI and in configuration tab, input the address of all deployed contracts and their ABIs.
8) once copied, click connect to contracts.
9) Now you can use this UI to test the functionality of code.

NOTE : For each account that you want to be able to sell its cards on the marketplace, you will have to call the setApprovalForAll function of cardregistry.sol (with input of marketplace address). In above steps we have already called this function using the admin account so that the card it creates can be sold. For example if account 2 buys a card but the function is not called from account2's address, no other account will be able to buy this card from account2. This is a design choice and doing this indicates that the account is allowing the marketplace to sell their cards on their behalf. 

