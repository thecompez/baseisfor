// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BaseIsFor.sol";

contract BaseNFTExtras {
    BaseNFT public baseNFT;

    struct NFTInfo {
        uint256 tokenId;
        string text;
        uint256 mintCount;
        uint256 boostCount;
        address firstMinter;
        bool isGolden;
        uint256 maxLevel;
    }

    mapping(string => bool) public isLockedWord;
    mapping(address => mapping(string => bool)) public hasGoldenBadge;
    string[] public lockedWords;

    event LockedWordUpdated(string text, bool isLocked);

    constructor(address _baseNFT) {
        baseNFT = BaseNFT(_baseNFT);
    }

    function addLockedWord(string memory text) external onlyOwner {
        require(!isLockedWord[text], "Word already locked");
        isLockedWord[text] = true;
        lockedWords.push(text);
        emit LockedWordUpdated(text, true);
    }

    function removeLockedWord(string memory text) external onlyOwner {
        require(isLockedWord[text], "Word not locked");
        isLockedWord[text] = false;
        uint256 len = lockedWords.length;
        for (uint256 i = 0; i < len; i++) {
            if (keccak256(abi.encodePacked(lockedWords[i])) == keccak256(abi.encodePacked(text))) {
                lockedWords[i] = lockedWords[len - 1];
                lockedWords.pop();
                emit LockedWordUpdated(text, false);
                break;
            }
        }
    }

    function awardGoldenBadges(string memory text) external onlyOwner {
        address[] memory minters = baseNFT.getTextMinters(text);
        uint256 len = minters.length;
        for (uint256 i = 0; i < len; i++) {
            address minter = minters[i];
            if (!hasGoldenBadge[minter][text]) {
                hasGoldenBadge[minter][text] = true;
                emit BaseNFT.GoldenBadgeEarned(minter, text);
            }
        }
    }

    function getLatestMinted(uint256 page, uint256 perPage) external view returns (NFTInfo[] memory) {
        uint256 total = baseNFT.totalMinted();
        if (total == 0) return new NFTInfo[](0);

        uint256 start = total > page * perPage ? total - (page * perPage) : 0;
        uint256 end = start > perPage ? start - perPage : 0;
        uint256 resultSize = start >= end ? start - end : 0;
        NFTInfo[] memory result = new NFTInfo[](resultSize);

        for (uint256 i = start; i > end && i > 0; i--) {
            uint256 tokenId = i;
            string memory text = baseNFT.tokenIdToText(tokenId);
            result[start - i] = NFTInfo({
                tokenId: tokenId,
                text: text,
                mintCount: baseNFT.textMintCount(text),
                boostCount: baseNFT.boostCount(text),
                firstMinter: baseNFT.firstMinter(text),
                isGolden: baseNFT.isGolden(text),
                maxLevel: baseNFT.textMaxLevel(text)
            });
        }
        return result;
    }

    function getMostMinted(uint256 page, uint256 perPage) external view returns (NFTInfo[] memory) {
        uint256 total = baseNFT.totalMinted();
        if (total == 0) return new NFTInfo[](0);

        NFTInfo[] memory allNFTs = new NFTInfo[](total);
        uint256 count = 0;

        for (uint256 i = 1; i <= total; i++) {
            string memory text = baseNFT.tokenIdToText(i);
            if (baseNFT.textToTokenId(text) == i) {
                allNFTs[count] = NFTInfo({
                    tokenId: i,
                    text: text,
                    mintCount: baseNFT.textMintCount(text),
                    boostCount: baseNFT.boostCount(text),
                    firstMinter: baseNFT.firstMinter(text),
                    isGolden: baseNFT.isGolden(text),
                    maxLevel: baseNFT.textMaxLevel(text)
                });
                count++;
            }
        }

        uint256 start = page * perPage;
        uint256 end = start + perPage > count ? count : start + perPage;
        uint256 resultSize = end > start ? end - start : 0;
        NFTInfo[] memory result = new NFTInfo[](resultSize);

        if (count > 1) {
            for (uint256 i = 0; i < count - 1; i++) {
                for (uint256 j = 0; j < count - i - 1; j++) {
                    if (allNFTs[j].mintCount < allNFTs[j + 1].mintCount) {
                        (allNFTs[j], allNFTs[j + 1]) = (allNFTs[j + 1], allNFTs[j]);
                    }
                }
            }
        }
        for (uint256 i = start; i < end && i < count; i++) {
            result[i - start] = allNFTs[i];
        }
        return result;
    }

    function getMostBoosted(uint256 page, uint256 perPage) external view returns (NFTInfo[] memory) {
        uint256 total = baseNFT.totalMinted();
        if (total == 0) return new NFTInfo[](0);

        uint256 boostedCount = 0;
        for (uint256 i = 1; i <= total; i++) {
            string memory text = baseNFT.tokenIdToText(i);
            if (baseNFT.textToTokenId(text) == i && baseNFT.isBoosted(text)) {
                boostedCount++;
            }
        }

        if (boostedCount == 0) return new NFTInfo[](0);

        NFTInfo[] memory boostedNFTs = new NFTInfo[](boostedCount);
        uint256 count = 0;

        for (uint256 i = 1; i <= total; i++) {
            string memory text = baseNFT.tokenIdToText(i);
            if (baseNFT.textToTokenId(text) == i && baseNFT.isBoosted(text)) {
                boostedNFTs[count] = NFTInfo({
                    tokenId: i,
                    text: text,
                    mintCount: baseNFT.textMintCount(text),
                    boostCount: baseNFT.boostCount(text),
                    firstMinter: baseNFT.firstMinter(text),
                    isGolden: baseNFT.isGolden(text),
                    maxLevel: baseNFT.textMaxLevel(text)
                });
                count++;
            }
        }

        uint256 start = page * perPage;
        uint256 end = start + perPage > count ? count : start + perPage;
        uint256 resultSize = end > start ? end - start : 0;
        NFTInfo[] memory result = new NFTInfo[](resultSize);

        if (count > 1) {
            for (uint256 i = 0; i < count - 1; i++) {
                for (uint256 j = 0; j < count - i - 1; j++) {
                    if (boostedNFTs[j].boostCount < boostedNFTs[j + 1].boostCount) {
                        (boostedNFTs[j], boostedNFTs[j + 1]) = (boostedNFTs[j + 1], boostedNFTs[j]);
                    }
                }
            }
        }
        for (uint256 i = start; i < end && i < count; i++) {
            result[i - start] = boostedNFTs[i];
        }
        return result;
    }

    function getTextLevels(string memory text) public view returns (uint256[] memory) {
        uint256 maxLevel = baseNFT.textMaxLevel(text);
        if (maxLevel == 0) return new uint256[](0);

        uint256[] memory fixedLevels = new uint256[](10);
        fixedLevels[0] = 8;
        fixedLevels[1] = 16;
        fixedLevels[2] = 32;
        fixedLevels[3] = 64;
        fixedLevels[4] = 128;
        fixedLevels[5] = 256;
        fixedLevels[6] = 512;
        fixedLevels[7] = 1024;
        fixedLevels[8] = 2048;
        fixedLevels[9] = 4096;

        uint256 validLevels;
        for (uint256 i = 0; i < 10; i++) {
            if (fixedLevels[i] > maxLevel) {
                validLevels = i;
                break;
            }
            if (i == 9) validLevels = 10;
        }

        uint256[] memory result = new uint256[](validLevels);
        for (uint256 i = 0; i < validLevels; i++) {
            result[i] = fixedLevels[i];
        }
        return result;
    }

    function getBoostCount(string memory text) external view returns (uint256) {
        return baseNFT.boostCount(text);
    }

    function isTextBoosted(string memory text) external view returns (bool) {
        return baseNFT.isBoosted(text);
    }

    function getLockedWords() external view returns (string[] memory) {
        return lockedWords;
    }

    function getUserPoints(address user) external view returns (uint256) {
        return baseNFT.userPoints(user);
    }

    function getCooldownRemaining(address user) external view returns (uint256) {
        uint256 lastUnlockTime = baseNFT.lastLockedWordUnlockTime(user);
        if (block.timestamp >= lastUnlockTime + baseNFT.getLockCooldown()) return 0;
        return (lastUnlockTime + baseNFT.getLockCooldown()) - block.timestamp;
    }

    function getUserTokens(address user) external view returns (uint256[] memory) {
        return baseNFT.getUserTokensArray(user);
    }

    function getTokenDetails(uint256 tokenId) external view returns (string memory text, string memory uri) {
        require(baseNFT.ownerOf(tokenId) != address(0));
        return (baseNFT.tokenIdToText(tokenId), baseNFT.tokenURI(tokenId));
    }

    modifier onlyOwner() {
        require(msg.sender == baseNFT.owner(), "Not owner");
        _;
    }
}
