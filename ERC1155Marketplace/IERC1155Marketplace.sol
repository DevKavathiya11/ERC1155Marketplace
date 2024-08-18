// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1155Marketplace {
    enum TokenType { ERC721, ERC1155 }

    
    event TokenListedForSale(address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 price);
    event TokenPurchased(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 price);
    event TokenCanceledFromSale(address indexed owner, uint256 indexed tokenId);
    event TokensPurchased(address indexed buyer, address indexed seller, uint256[] indexed tokenIds, uint256[] amounts, uint256 totalPrice); // Added
    event TokenListedForAuction(address indexed seller, uint256 indexed tokenId, uint256 basePrice, uint256 duration, uint256 amount, TokenType tokenType);
    event NewBid(address indexed bidder, uint256 indexed tokenId, uint256 bidAmount);
    event AuctionSettled(uint256 indexed tokenId, address indexed winner, uint256 winningBid);
    event AuctionCanceled(uint256 indexed tokenId, address indexed seller);


    function listTokenForSale(uint256 id_, uint256 amount_, uint256 price_, TokenType tokenType_) external;
    function buyToken(uint256 id_, uint256 amount_) external payable;
    function cancelTokenOnSale(uint256 id_, TokenType tokenType_) external;
    function batchBuyTokens(uint256[] calldata ids_, uint256[] calldata amounts_) external payable;
    function putTokenOnAuction(
        uint256 tokenId_,
        uint256 basePrice_,
        uint256 duration_,
        uint256 amount_,
        TokenType tokenType_
    ) external;
    function bidOnAuction(uint256 tokenId_) external payable;
    function settleAuction(uint256 tokenId_) external;
    function cancelAuction(uint256 tokenId_) external;
}
