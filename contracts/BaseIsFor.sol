// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract BaseNFT is ERC721URIStorage, Ownable, Pausable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    uint256 public constant BASE_MINT_PRICE_ETH = 0.000256 ether;
    uint256 public constant LOCK_COOLDOWN = 30 days;
    uint256 public constant MAX_LEVEL_CAP = 4096;
    uint256 public devPool;
    uint256 public communityPool;

    mapping(string => uint256) public textMintCount;
    mapping(uint256 => string) public tokenIdToText;
    mapping(address => uint256[]) public userTokens;
    mapping(address => mapping(string => uint256)) public userTextMintCount;
    mapping(string => uint256) public textToTokenId;
    mapping(string => address) public firstMinter;
    mapping(string => address[]) public textMinters;
    mapping(string => uint256) public textETHCollected;
    mapping(string => mapping(address => mapping(uint256 => bool))) public hasClaimedReward;
    mapping(address => uint256) public userPoints;
    mapping(string => bool) public isGolden;
    mapping(address => bool) public hasBoosterBadge;
    mapping(address => uint256) public lastLockedWordUnlockTime;
    mapping(string => uint256) public textMaxLevel;
    mapping(string => bool) public isBoosted;
    mapping(string => uint256) public boostCount;

    event Minted(address indexed user, uint256 tokenId, string text);
    event RewardClaimed(address indexed user, string text, uint256 amount, uint256 level);
    event BoosterBadgeEarned(address indexed user);
    event GoldenBadgeEarned(address indexed user, string text);
    event LockedWordUnlocked(address indexed booster, string text);
    event ETHWithdrawn(address indexed owner, uint256 amount);
    event Boosted(address indexed user, string text, uint256 count);

    constructor() ERC721("BaseNFT", "BNFT") Ownable(msg.sender) {
        _tokenIdCounter.reset();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function mintWithETH(string memory tokenURI, string memory text, uint256 maxLevel, bool isLocked) external payable whenNotPaused nonReentrant {
        uint256 mintPrice = getMintPrice(text);
        require(msg.value >= mintPrice, "Insufficient ETH");
        require(bytes(text).length > 0 && bytes(text).length <= 50, "Invalid text length");
        require(maxLevel <= MAX_LEVEL_CAP && maxLevel >= 8, "Invalid max level");

        if (isLocked && textToTokenId[text] == 0) {
            require(hasBoosterBadge[msg.sender], "No Booster Badge");
            require(userPoints[msg.sender] >= 100, "Not enough points");
            require(block.timestamp >= lastLockedWordUnlockTime[msg.sender] + LOCK_COOLDOWN, "Cooldown active");
            lastLockedWordUnlockTime[msg.sender] = block.timestamp;
            emit LockedWordUnlocked(msg.sender, text);
        }
        if (textToTokenId[text] == 0) {
            textMaxLevel[text] = maxLevel;
        }
        _mintSingle(msg.sender, tokenURI, text, msg.value);
    }

    function mintMultipleWithETH(string memory tokenURI, string memory text, uint256 count) external payable whenNotPaused nonReentrant {
        require(count == 2 || count == 4 || count == 8 || count == 16 || count == 32, "Invalid count");
        require(msg.sender != firstMinter[text], "Genesis cannot boost");
        require(textToTokenId[text] != 0, "Text not initialized");
        uint256 currentMintCount = textMintCount[text];
        uint256 maxLevel = textMaxLevel[text];
        require(currentMintCount < maxLevel, "Max level reached");
        uint256 remainingCapacity = maxLevel - currentMintCount;
        require(count <= remainingCapacity, "Boost exceeds capacity");

        uint256 mintPrice = BASE_MINT_PRICE_ETH;
        uint256 totalCost = mintPrice * count;
        require(msg.value >= totalCost, "Insufficient ETH");

        for (uint256 i = 0; i < count; i++) {
            _mintSingle(msg.sender, tokenURI, text, totalCost / count);
        }
        isBoosted[text] = true;
        boostCount[text] += count;
        emit Boosted(msg.sender, text, count);

        if (!hasBoosterBadge[msg.sender]) {
            hasBoosterBadge[msg.sender] = true;
            emit BoosterBadgeEarned(msg.sender);
        }
        userPoints[msg.sender] += count * 2;
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
    }

    function _mintSingle(address sender, string memory tokenURI, string memory text, uint256 value) internal {
        uint256 tokenId = textToTokenId[text];
        bool isFirstMint = tokenId == 0;

        if (isFirstMint) {
            _tokenIdCounter.increment();
            tokenId = _tokenIdCounter.current();
            textToTokenId[text] = tokenId;
            tokenIdToText[tokenId] = text;
            _safeMint(sender, tokenId);
            firstMinter[text] = sender;
            userTokens[sender].push(tokenId);
            userPoints[sender] += 10;
        }

        _setTokenURI(tokenId, tokenURI);
        textMintCount[text]++;
        userTextMintCount[sender][text]++;
        if (userTextMintCount[sender][text] == 1) {
            textMinters[text].push(sender);
        }

        uint256 devShare = value * 15 / 100;
        uint256 poolShare = value * 15 / 100;
        uint256 rewardShare = value * 70 / 100;
        devPool += devShare;
        if (textMintCount[text] <= textMaxLevel[text]) {
            textETHCollected[text] += rewardShare;
        } else {
            communityPool += rewardShare;
            if (!isGolden[text] && textMaxLevel[text] > 512) {
                isGolden[text] = true;
                emit GoldenBadgeEarned(sender, text);
            }
        }
        communityPool += poolShare;

        _updatePoints(sender, text);
        emit Minted(sender, tokenId, text);
    }

    function claimReward(string memory text, uint256 level) external whenNotPaused nonReentrant {
        uint256 maxLevel = textMaxLevel[text];
        require(maxLevel > 0, "Text not initialized");

        uint256[] memory levels = new uint256[](10);
        levels[0] = 8; levels[1] = 16; levels[2] = 32; levels[3] = 64; levels[4] = 128;
        levels[5] = 256; levels[6] = 512; levels[7] = 1024; levels[8] = 2048; levels[9] = 4096;

        uint256 validLevels;
        for (uint256 i = 0; i < 10; i++) {
            if (levels[i] > maxLevel) {
                validLevels = i;
                break;
            }
            if (i == 9) validLevels = 10;
        }

        require(level < validLevels, "Invalid level");
        require(textMintCount[text] >= levels[level], "Level not reached");
        require(!hasClaimedReward[text][msg.sender][level], "Reward claimed");
        require(userTextMintCount[msg.sender][text] > 0, "No contribution");

        uint256 totalReward = textETHCollected[text];
        uint256 totalMints = textMintCount[text];
        uint256 amount;

        if (msg.sender == firstMinter[text]) {
            amount = totalReward * 10 / 100;
            userPoints[msg.sender] += level + 1;
        } else {
            uint256 userContribution = userTextMintCount[msg.sender][text];
            amount = (totalReward * 60 / 100) * userContribution / totalMints;
            userPoints[msg.sender] += (level + 1) * userContribution;
        }

        hasClaimedReward[text][msg.sender][level] = true;
        textETHCollected[text] -= amount;
        payable(msg.sender).transfer(amount);
        emit RewardClaimed(msg.sender, text, amount, level);
    }

    function getMintPrice(string memory text) public view returns (uint256) {
        if (textToTokenId[text] == 0) return BASE_MINT_PRICE_ETH;
        uint256 mintCount = textMintCount[text];
        uint256 maxLevel = textMaxLevel[text];
        if (mintCount < maxLevel) return BASE_MINT_PRICE_ETH;
        if (maxLevel <= 64) return BASE_MINT_PRICE_ETH * 2;
        if (maxLevel <= 512) return BASE_MINT_PRICE_ETH * 4;
        return BASE_MINT_PRICE_ETH * 8;
    }

    function withdrawDevPool() external onlyOwner {
        uint256 amount = devPool;
        devPool = 0;
        payable(owner()).transfer(amount);
        emit ETHWithdrawn(owner(), amount);
    }

    function withdrawCommunityPool() external onlyOwner {
        uint256 amount = communityPool;
        communityPool = 0;
        payable(owner()).transfer(amount);
        emit ETHWithdrawn(owner(), amount);
    }

    function _updatePoints(address sender, string memory text) internal {
        userPoints[sender] += isGolden[text] ? 16 : (textMintCount[text] % 10 == 0 ? 6 : 1);
    }

    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter.current();
    }

    function getTextMinters(string memory text) external view returns (address[] memory) {
        return textMinters[text];
    }

    function getUserTokensArray(address user) external view returns (uint256[] memory) {
        return userTokens[user];
    }

    function getLockCooldown() external pure returns (uint256) {
        return LOCK_COOLDOWN;
    }
}
