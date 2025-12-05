let web3;
let cardRegistry;
let marketplace;
let graderContract;
let accounts = [];
let currentAccount;
let contractOwner = null; // Chg A1
let isCurrentGrader = false; // Chg A3

// Upload a file to local IPFS node and return its CID  // Chg A6
async function uploadFileToIPFS(file) {                 // Chg A6
    // IMPORTANT: must be the IPFS API, NOT port 5500
    const apiUrl = 'http://127.0.0.1:5001/api/v0/add?pin=true';  // Chg A6

    const formData = new FormData();
    formData.append('file', file);

    const res = await fetch(apiUrl, {
        method: 'POST',
        body: formData
    });

    if (!res.ok) {
        console.error('IPFS add response not OK:', res.status, res.statusText);
        throw new Error('IPFS upload failed with status ' + res.status);
    }

    const text = await res.text();
    console.log('IPFS add raw response:', text); // helpful for debugging

    const lines = text.trim().split('\n');
    const last = lines[lines.length - 1];
    const data = JSON.parse(last);

    return data.Hash; // CID string
}

// === Navigation helper (Chg A2 + A3) ===
function navigate(page) {
    // Chg A2
    const pages = ['home', 'market', 'config', 'create']; // include create page - Chg A3
    pages.forEach(p => {
        const el = document.getElementById('page-' + p);
        if (el) el.style.display = (p === page) ? 'block' : 'none';
    });

    const links = document.querySelectorAll('.nav-link');
    links.forEach(link => {
        const isActive = link.dataset.page === page;
        link.classList.toggle('active', isActive);
    });
}

// Initialize Web3 and load accounts
async function initialize() {
    try {
        web3 = new Web3('http://127.0.0.1:8545');
        showSuccess('Connected to local node');

        accounts = await web3.eth.getAccounts();
        currentAccount = accounts[0];

        const select = document.getElementById('accountSelect');
        select.innerHTML = '<option value="">Select Account...</option>';
        accounts.forEach((acc, index) => {
            const option = document.createElement('option');
            option.value = acc;
            option.text = `Account ${index}: ${acc.substring(0, 10)}...`;
            select.appendChild(option);
        });
        select.value = currentAccount;

        await updateAccountInfo();
        loadConfig();
        navigate('home'); // default - Chg A2

    } catch (error) {
        showError('Connection error: ' + error.message);
    }
}

// Initialize contracts
async function initializeContracts() {
    try {
        const cardRegAddr = document.getElementById('cardRegistryAddress').value;
        const marketAddr = document.getElementById('marketplaceAddress').value;
        const graderAddr = document.getElementById('graderAddress').value;

        const cardRegABI = JSON.parse(document.getElementById('cardRegistryABI').value);
        const marketABI = JSON.parse(document.getElementById('marketplaceABI').value);
        const graderABI = JSON.parse(document.getElementById('graderABI').value);

        cardRegistry = new web3.eth.Contract(cardRegABI, cardRegAddr);
        marketplace = new web3.eth.Contract(marketABI, marketAddr);
        graderContract = new web3.eth.Contract(graderABI, graderAddr);

        // Get contract owner (company)
        contractOwner = await cardRegistry.methods.owner().call(); // Chg A1

        showSuccess('Contracts initialized successfully!');
        updateCreateSectionVisibility(); // Chg A1
        await updateGraderControlsVisibility(); // Chg A3
        loadCards();
        loadQueue();

    } catch (error) {
        showError('Error initializing contracts: ' + error.message);
    }
}

// Switch account
async function switchAccount() {
    const select = document.getElementById('accountSelect');
    currentAccount = select.value;
    await updateAccountInfo();
    updateCreateSectionVisibility(); // Chg A1
    await updateGraderControlsVisibility(); // Chg A3
    loadCards();
    loadQueue();
}

// Update account info
async function updateAccountInfo() {
    document.getElementById('currentAccount').textContent =
        currentAccount ? currentAccount.substring(0, 20) + '...' : 'Not connected';

    if (currentAccount) {
        const balance = await web3.eth.getBalance(currentAccount);
        document.getElementById('accountBalance').textContent =
            web3.utils.fromWei(balance, 'ether') + ' ETH';
    }
}

// Owner-only visibility for Create Card + nav button
function updateCreateSectionVisibility() {
    // Chg A1 + A3
    const section = document.getElementById('createCardSection');
    const navCreate = document.getElementById('navCreate'); // Chg A3
    const pageCreate = document.getElementById('page-create'); // Chg A3
    if (!section || !navCreate || !pageCreate) return;

    if (!contractOwner || !currentAccount) {
        section.style.display = 'none';
        navCreate.style.display = 'none';
        if (pageCreate.style.display !== 'none') {
            navigate('home'); // Chg A3
        }
        return;
    }

    const isOwner =
        contractOwner.toLowerCase() === currentAccount.toLowerCase();

    if (isOwner) {
        section.style.display = '';
        navCreate.style.display = 'inline-block'; // show Create tab - Chg A3
    } else {
        section.style.display = 'none';
        navCreate.style.display = 'none';
        if (pageCreate.style.display !== 'none') {
            navigate('home'); // if we were on hidden page, go home - Chg A3
        }
    }
}

// Check if current account is an authorized grader and toggle the button
async function updateGraderControlsVisibility() {
    // Chg A3
    const btn = document.getElementById('gradeNextBtn');
    if (!btn) return;

    if (!graderContract || !currentAccount) {
        btn.style.display = 'none';
        isCurrentGrader = false;
        return;
    }

    try {
        const authorized = await graderContract.methods
            .authorizedGraders(currentAccount)
            .call();

        isCurrentGrader = authorized;
        btn.style.display = authorized ? '' : 'none';
    } catch (error) {
        console.error('Error checking grader status:', error);
        btn.style.display = 'none';
        isCurrentGrader = false;
    }
}

// Create a new card (one click = upload image to IPFS + mint card)  // Chg A6
async function createCard() {                                       // Chg A6
    if (!cardRegistry) {
        showError('Please initialize contracts first');
        return;
    }

    const name = document.getElementById('cardName').value.trim();
    const priceEth = document.getElementById('price').value;
    //const cidField = document.getElementById('metadataCID');
    //const cidInput = cidField.value.trim();
    const imageFile = document.getElementById('cardImageFile')
        ? document.getElementById('cardImageFile').files[0]
        : null;

    if (!name || !priceEth) {
        showError('Please fill Card Name and Price');
        return;
    }

    let finalCID = null;

    try {
        // 1) If a file is selected, upload it to IPFS and use that CID
        if (imageFile) {
            showSuccess('Uploading image to IPFS...');
            finalCID = await uploadFileToIPFS(imageFile);
            // cidField.value = finalCID; // auto-fill field so you can see it
            showSuccess('Image uploaded to IPFS. CID: ' + finalCID);
        }

        // 2) If still no CID, block minting → avoids cards without images
        if (!finalCID) {
            showError('No metadata CID. Please upload an image');
            return;
        }

        const priceWei = web3.utils.toWei(priceEth, 'ether');

        // 3) Mint the card on-chain with the CID
        const gasEstimate = await cardRegistry.methods
            .createCard(currentAccount, name, finalCID, priceWei)
            .estimateGas({ from: currentAccount });

        const gasLimit = Math.floor(gasEstimate * 1.5);

        const result = await cardRegistry.methods
            .createCard(currentAccount, name, finalCID, priceWei)
            .send({
                from: currentAccount,
                gas: gasLimit
            });

        const tokenId = result.events.CardCreated.returnValues.tokenId;
        showSuccess('Card created successfully! Token ID: ' + tokenId);

        // 4) Auto-list in marketplace
        const listGasEstimate = await marketplace.methods
            .autoList(tokenId)
            .estimateGas({ from: currentAccount });

        await marketplace.methods.autoList(tokenId).send({
            from: currentAccount,
            gas: Math.floor(listGasEstimate * 1.5)
        });

        // 5) Refresh UI
        loadCards();

        // Clear inputs (but leave CID so user sees what it was)
        document.getElementById('cardName').value = '';
        if (document.getElementById('cardImageFile')) {
            document.getElementById('cardImageFile').value = '';
        }
        document.getElementById('price').value = '';

    } catch (error) {
        showError('Error creating card: ' + error.message);
        console.error('Full error in createCard:', error);
    }
}

// Authorize a grader (owner only)
async function authorizeGrader() {
    const graderAddr = document.getElementById('graderAccountAddress').value.trim();
    if (!graderAddr) {
        showError('Please enter a grader address');
        return;
    }
    if (!graderContract) {
        showError('Please initialize contracts first');
        return;
    }

    try {
        const gasEstimate = await graderContract.methods
            .setGrader(graderAddr, true)
            .estimateGas({ from: currentAccount });

        await graderContract.methods
            .setGrader(graderAddr, true)
            .send({
                from: currentAccount,
                gas: Math.floor(gasEstimate * 1.5)
            });

        showSuccess('Grader authorized successfully!');
        if (graderAddr.toLowerCase() === currentAccount.toLowerCase()) {
            await updateGraderControlsVisibility(); // Chg A3
        }
    } catch (error) {
        showError('Error authorizing grader: ' + error.message);
        console.error('Full error:', error);
    }
}

// Load cards: show only listed ones in Market, with grading option for owner  // Chg A11
async function loadCards() {                                                   // Chg A11
    if (!cardRegistry || !marketplace) return;

    try {
        const cardsDiv = document.getElementById('cards');
        cardsDiv.innerHTML = '<div class="loading">Loading cards...</div>';

        const totalMinted = await cardRegistry.methods.totalMinted().call();

        cardsDiv.innerHTML = '';

        let listedCount = 0;

        for (let i = 1; i <= totalMinted; i++) {
            const card = await cardRegistry.methods.getCard(i).call();
            const owner = await cardRegistry.methods.ownerOf(i).call();
            const listingInfo = await marketplace.methods.getListingInfo(i).call();

            // Show only cards that are listed in the marketplace
            if (!listingInfo.isListed) continue;
            listedCount++;

            const cardDiv = document.createElement('div');
            cardDiv.className = 'card';

            const isOwner =
                currentAccount &&
                owner.toLowerCase() === currentAccount.toLowerCase();

            const gradeBadge = card.graded
                ? `<span class="badge graded">Grade: ${card.grade}</span>`
                : `<span class="badge ungraded">Ungraded</span>`;

            const listedBadge = `<span class="badge listed">Listed</span>`;

            // Build image URL from metadataCID via local IPFS gateway
            let imageUrl = '';
            if (card.metadataCID && card.metadataCID.trim() !== '') {
                const cid = card.metadataCID.trim();
                if (cid.startsWith('http://') || cid.startsWith('https://')) {
                    imageUrl = cid;
                } else if (cid.startsWith('ipfs://')) {
                    imageUrl = 'http://127.0.0.1:8080/ipfs/' + cid.replace('ipfs://', '');
                } else {
                    imageUrl = 'http://127.0.0.1:8080/ipfs/' + cid;
                }
            }
            const imgHtml = imageUrl
                ? `<div class="card-image-wrapper"><img class="card-image" src="${imageUrl}" alt="${card.name}"></div>`
                : '';

            // Buttons
            const buyButton = !isOwner
                ? `<button onclick="buyCard(${i}, '${card.metadataCID}')">💰 Buy Card</button>`
                : '';

            const ownerButtons = isOwner
                ? `
                            <button onclick="updatePrice(${i})" class="secondary">💲 Update Price</button>
                            ${!card.graded
                    ? `<button onclick="requestGrading(${i})" class="success">⭐ Request Grading</button>`
                    : ''
                }
                        `
                : '';

            cardDiv.innerHTML = `
                        <h3>${card.name}</h3>
                        ${imgHtml}
                        ${gradeBadge}
                        ${listedBadge}
                        <div class="card-info"><strong>Token ID:</strong> ${i}</div>
                        <div class="card-info"><strong>Price:</strong> ${web3.utils.fromWei(card.price, 'ether')} ETH</div>
                        <div class="card-info"><strong>Owner:</strong> ${owner.substring(0, 15)}...</div>
                        <div class="card-info" style="word-break: break-all;">
                            <strong>CID:</strong> ${card.metadataCID}
                        </div>
                        <div class="card-info"><strong>Created:</strong> ${new Date(card.createdAt * 1000).toLocaleDateString()}</div>

                        <div class="card-actions">
                            ${buyButton}
                            ${ownerButtons}
                            <button onclick="viewHistory(${i})">📜 View History</button>
                        </div>
                    `;

            cardsDiv.appendChild(cardDiv);
        }

        if (listedCount === 0) {
            cardsDiv.innerHTML =
                '<p style="text-align:center; color:#666;">No cards currently listed in the marketplace.</p>';
        }
    } catch (error) {
        showError('Error loading cards: ' + error.message);
        console.error('loadCards error:', error);
    }
}



// Buy a card
async function buyCard(tokenId, expectedCID) {
    try {
        const price = await cardRegistry.methods.getPrice(tokenId).call();

        const gasEstimate = await marketplace.methods
            .buy(tokenId, expectedCID)
            .estimateGas({
                from: currentAccount,
                value: price
            });

        await marketplace.methods
            .buy(tokenId, expectedCID)
            .send({
                from: currentAccount,
                value: price,
                gas: Math.floor(gasEstimate * 1.5)
            });

        showSuccess('Card purchased successfully!');
        loadCards();
        await updateAccountInfo();

    } catch (error) {
        showError('Error buying card: ' + error.message);
        console.error('Full error:', error);
    }
}

// Update card price
async function updatePrice(tokenId) {
    const newPrice = prompt('Enter new price in ETH:');
    if (!newPrice) return;

    try {
        const priceWei = web3.utils.toWei(newPrice, 'ether');

        const gasEstimate = await cardRegistry.methods
            .setPrice(tokenId, priceWei)
            .estimateGas({ from: currentAccount });

        await cardRegistry.methods
            .setPrice(tokenId, priceWei)
            .send({
                from: currentAccount,
                gas: Math.floor(gasEstimate * 1.5)
            });

        showSuccess('Price updated successfully!');
        loadCards();

    } catch (error) {
        showError('Error updating price: ' + error.message);
        console.error('Full error:', error);
    }
}

// List card
async function listCard(tokenId) {
    try {
        const gasEstimate = await marketplace.methods
            .list(tokenId)
            .estimateGas({ from: currentAccount });

        await marketplace.methods.list(tokenId).send({
            from: currentAccount,
            gas: Math.floor(gasEstimate * 1.5)
        });
        showSuccess('Card listed successfully!');
        loadCards();
    } catch (error) {
        showError('Error listing card: ' + error.message);
        console.error('Full error:', error);
    }
}

// Request grading
async function requestGrading(tokenId) {
    try {
        const fee = await graderContract.methods.gradingFee().call();

        const gasEstimate = await graderContract.methods
            .enqueueForGrading(tokenId)
            .estimateGas({
                from: currentAccount,
                value: fee
            });

        await graderContract.methods
            .enqueueForGrading(tokenId)
            .send({
                from: currentAccount,
                value: fee,
                gas: Math.floor(gasEstimate * 1.5)
            });

        showSuccess('Card enqueued for grading!');
        loadQueue();

    } catch (error) {
        showError('Error requesting grading: ' + error.message);
        console.error('Full error:', error);
    }
}

// Load grading queue and show each request as a mini-card - Chg A10
async function loadQueue() { // Chg A10
    if (!graderContract || !cardRegistry) return;

    const queueDiv = document.getElementById('queueInfo');
    const listDiv = document.getElementById('queueList');

    try {
        listDiv.innerHTML = '<div class="loading">Loading queue...</div>';

        const queueLength = await graderContract.methods.queueLength().call();
        const totalProcessed = await graderContract.methods.totalProcessed().call();

        // Summary info
        queueDiv.innerHTML = `
                    <p><strong>Queue Length:</strong> ${queueLength}</p>
                    <p><strong>Total Processed:</strong> ${totalProcessed}</p>
                `;

        if (queueLength == 0) {
            listDiv.innerHTML =
                '<p style="color:#666;">No cards currently waiting for grading.</p>';
            return;
        }

        // Get list of pending tokenIds
        const tokenIds = await graderContract.methods.getPendingQueue().call(); // Chg A10

        listDiv.innerHTML = '';

        for (const tokenId of tokenIds) {
            // Fetch card + owner
            const card = await cardRegistry.methods.getCard(tokenId).call();
            const owner = await cardRegistry.methods.ownerOf(tokenId).call();

            // Optional: grading request info (requester, time)
            let reqInfo = null;
            try {
                // public mapping getter
                reqInfo = await graderContract.methods.gradingRequests(tokenId).call();
            } catch (e) {
                console.warn('Could not load gradingRequests for token', tokenId, e);
            }

            // Build image URL from metadataCID via local gateway (same as market) - Chg A10
            let imageUrl = '';
            if (card.metadataCID && card.metadataCID.trim() !== '') {
                const cid = card.metadataCID.trim();
                if (cid.startsWith('http://') || cid.startsWith('https://')) {
                    imageUrl = cid;
                } else if (cid.startsWith('ipfs://')) {
                    imageUrl = 'http://127.0.0.1:8080/ipfs/' + cid.replace('ipfs://', '');
                } else {
                    imageUrl = 'http://127.0.0.1:8080/ipfs/' + cid;
                }
            }

            const wrapper = document.createElement('div');
            wrapper.className = 'queue-card';

            const requestedAt =
                reqInfo && reqInfo.requestTime && reqInfo.requestTime !== '0'
                    ? new Date(Number(reqInfo.requestTime) * 1000).toLocaleString()
                    : '—';

            const requesterShort =
                reqInfo && reqInfo.requester
                    ? reqInfo.requester.substring(0, 15) + '...'
                    : 'Unknown';

            wrapper.innerHTML = `
                        <div class="queue-card-image-wrapper">
                            ${imageUrl
                    ? `<img class="queue-card-image" src="${imageUrl}" alt="${card.name}">`
                    : `<div class="queue-card-placeholder">No Image</div>`
                }
                        </div>
                        <div class="queue-card-details">
                            <h4>${card.name} (Token #${tokenId})</h4>
                            <p><strong>Owner:</strong> ${owner.substring(0, 20)}...</p>
                            <p><strong>Requested By:</strong> ${requesterShort}</p>
                            <p><strong>Requested At:</strong> ${requestedAt}</p>
                        </div>
                    `;

            listDiv.appendChild(wrapper);
        }
    } catch (error) {
        console.error('Error loading queue:', error);
        queueDiv.innerHTML =
            '<p>Error loading queue: ' + error.message + '</p>';
        listDiv.innerHTML = '';
    }
}


// Process next in queue (grader only)
async function processNextInQueue() {
    if (!isCurrentGrader) {
        // Chg A3
        showError('Selected account is not an authorized grader.');
        return;
    }

    const grade = prompt('Enter grade (1-10):');
    if (!grade) return;

    // const newCID = prompt('Enter new metadata CID with grade:');
    // if (!newCID) return;

    try {
        const result = await graderContract.methods.peek().call();
        const nextToken = result.tokenId;
        const exists = result.exists;
        if (!exists) {
            showError('Queue is empty');
            return;
        }
        // ---- Fetch existing CID from CardRegistry ----
        const cardData = await cardRegistry.methods.getCard(nextToken).call();
        const currentCID = cardData.metadataCID;
        const gasEstimate = await graderContract.methods
            .grade(nextToken, grade, currentCID)
            .estimateGas({ from: currentAccount });

        await graderContract.methods
            .grade(nextToken, grade, currentCID)
            .send({
                from: currentAccount,
                gas: Math.floor(gasEstimate * 1.5)
            });

        showSuccess('Card graded successfully!');
        loadQueue();
        loadCards();

    } catch (error) {
        showError('Error grading card: ' + error.message);
        console.error('Full error:', error);
    }
}

// View ownership history
async function viewHistory(tokenId) {
    try {
        const history = await cardRegistry.methods.getOwnershipHistory(tokenId).call();
        const card = await cardRegistry.methods.getCard(tokenId).call();

        let html = `<h2>📜 Ownership History - ${card.name}</h2>`;
        html += `<p style="margin: 15px 0; color: #666;">Token ID: ${tokenId}</p>`;

        history.forEach((record, index) => {
            const date = new Date(record.timestamp * 1000);
            html += `
                        <div class="history-item">
                            <strong>Transfer ${index + 1}</strong><br>
                            Owner: ${record.owner}<br>
                            Date: ${date.toLocaleString()}<br>
                            Price: ${web3.utils.fromWei(record.price, 'ether')} ETH
                        </div>
                    `;
        });

        showModal(html);

    } catch (error) {
        showError('Error viewing history: ' + error.message);
    }
}

// Modal functions
function showModal(content) {
    document.getElementById('modalContent').innerHTML = content;
    document.getElementById('modal').style.display = 'block';
}

function closeModal() {
    document.getElementById('modal').style.display = 'none';
}

// Save/Load configuration
function saveConfig() {
    const config = {
        cardRegistryAddress: document.getElementById('cardRegistryAddress').value,
        marketplaceAddress: document.getElementById('marketplaceAddress').value,
        graderAddress: document.getElementById('graderAddress').value,
        cardRegistryABI: document.getElementById('cardRegistryABI').value,
        marketplaceABI: document.getElementById('marketplaceABI').value,
        graderABI: document.getElementById('graderABI').value
    };

    localStorage.setItem('pokemonCardConfig', JSON.stringify(config));
    showSuccess('Configuration saved!');
}

function loadConfig() {
    const saved = localStorage.getItem('pokemonCardConfig');
    if (saved) {
        const config = JSON.parse(saved);
        document.getElementById('cardRegistryAddress').value = config.cardRegistryAddress || '';
        document.getElementById('marketplaceAddress').value = config.marketplaceAddress || '';
        document.getElementById('graderAddress').value = config.graderAddress || '';
        document.getElementById('cardRegistryABI').value = config.cardRegistryABI || '';
        document.getElementById('marketplaceABI').value = config.marketplaceABI || '';
        document.getElementById('graderABI').value = config.graderABI || '';
        showSuccess('Configuration loaded!');
    }
}

// Notification helpers
function showSuccess(message) {
    const status = document.getElementById('connection-status');
    status.className = '';
    status.textContent = '✅ ' + message;
}

function showError(message) {
    const status = document.getElementById('connection-status');
    status.className = 'error';
    status.textContent = '❌ ' + message;
}

// Initialize on page load
window.onload = initialize;

// Close modal on outside click
window.onclick = function (event) {
    const modal = document.getElementById('modal');
    if (event.target == modal) {
        closeModal();
    }
}