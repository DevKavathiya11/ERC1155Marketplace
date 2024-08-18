// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC1155Marketplace.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC1155Marketplace is IERC1155Marketplace, ReentrancyGuard {
    struct TokenData {
        uint256 tokenId;
        uint256 price;
        address owner;
        uint256 amount;
        TokenType tokenType;
        bool isActive;
    }

    struct Auction {
        uint256 basePrice;
        address seller;
        uint256 highestBid;
        address highestBidder;
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
        TokenType tokenType;
        bool isActive;
    }

    IERC1155 private _erc1155Contract;
    IERC721 private _erc721Contract;

    mapping(uint256 => TokenData) private _tokens;
    mapping(uint256 => Auction) private _auctions;

    uint256[] private _listedTokens;
    uint256[] private _tokensOnAuction;

    constructor(address erc1155ContractAddress_, address erc721ContractAddress_)
    {
        _erc1155Contract = IERC1155(erc1155ContractAddress_);
        _erc721Contract = IERC721(erc721ContractAddress_);
    }

    function listTokenForSale(
        uint256 id_,
        uint256 amount_,
        uint256 price_,
        TokenType tokenType_
    ) public nonReentrant {
        if (tokenType_ == TokenType.ERC721) {
            require(
                !_auctions[id_].isActive ||
                    _auctions[id_].tokenType != TokenType.ERC721,
                "ERC1155Marketplace: Auction is active for ERC721 token"
            );
        } else {
            require(
                !_auctions[id_].isActive ||
                    _auctions[id_].tokenType != TokenType.ERC1155,
                "ERC1155Marketplace: Auction is active for ERC1155 token"
            );
        }
        require(price_ > 0, "ERC1155Marketplace: Price must be greater than 0");

        if (tokenType_ == TokenType.ERC721) {
            try _erc721Contract.ownerOf(id_) returns (address owner) {
                require(
                    amount_ == 0,
                    "ERC1155Marketplace: Amount must be 0 for ERC721 tokens"
                );
                require(
                    !_tokens[id_].isActive,
                    "ERC1155Marketplace: Already at Sale"
                );
                require(
                    owner == msg.sender,
                    "ERC1155Marketplace: You do not own this ERC721 token"
                );
                require(
                    _erc721Contract.isApprovedForAll(
                        msg.sender,
                        address(this)
                    ) || _erc721Contract.getApproved(id_) == address(this),
                    "ERC1155Marketplace: Marketplace not approved for ERC721"
                );

                _tokens[id_] = TokenData({
                    tokenId: id_,
                    price: price_,
                    owner: msg.sender,
                    amount: 0,
                    tokenType: TokenType.ERC721,
                    isActive: true
                });
            } catch {
                revert("ERC1155Marketplace: Token doesn't exist");
            }
        } else {
            require(
                !_tokens[id_].isActive,
                "ERC1155Marketplace: Already at Sale"
            );
            require(
                _erc1155Contract.isApprovedForAll(msg.sender, address(this)),
                "ERC1155Marketplace: Marketplace not approved for ERC1155"
            );
            require(
                _erc1155Contract.balanceOf(msg.sender, id_) >= amount_,
                "ERC1155Marketplace: Insufficient ERC1155 token balance"
            );
            require(
                amount_ > 0,
                "ERC1155Marketplace: Amount must be greater than 0"
            );

            _tokens[id_] = TokenData({
                tokenId: id_,
                price: price_,
                owner: msg.sender,
                amount: amount_,
                tokenType: TokenType.ERC1155,
                isActive: true
            });
        }

        _listedTokens.push(id_);
        emit TokenListedForSale(msg.sender, id_, amount_, price_);
    }

    function buyToken(uint256 id_, uint256 amount_)
        public
        payable
        nonReentrant
    {
        TokenData storage tokenData = _tokens[id_];
        require(
            tokenData.owner != address(0),
            "ERC1155Marketplace: Token has not been listed"
        );
        require(
            msg.sender != tokenData.owner,
            "ERC1155Marketplace: You are the owner"
        );

        uint256 totalPrice = tokenData.tokenType == TokenType.ERC721
            ? tokenData.price
            : tokenData.price * amount_;
        require(
            msg.value >= totalPrice,
            "ERC1155Marketplace: Insufficient Payment"
        );

        if (tokenData.tokenType == TokenType.ERC721) {
            require(
                amount_ == 0,
                "ERC1155Marketplace: Amount must be 0 for ERC721 tokens"
            );
            require(
                _erc721Contract.isApprovedForAll(
                    tokenData.owner,
                    address(this)
                ) || _erc721Contract.getApproved(id_) == address(this),
                "ERC1155Marketplace: Marketplace not approved for ERC721"
            );

            _erc721Contract.safeTransferFrom(tokenData.owner, msg.sender, id_);
        } else {
            require(
                _erc1155Contract.isApprovedForAll(
                    tokenData.owner,
                    address(this)
                ),
                "ERC1155Marketplace: Marketplace not approved for ERC1155"
            );
            require(
                amount_ > 0 && amount_ <= tokenData.amount,
                "ERC1155Marketplace: Amount exceeds listed amount"
            );

            _erc1155Contract.safeTransferFrom(
                tokenData.owner,
                msg.sender,
                id_,
                amount_,
                ""
            );
            tokenData.amount -= amount_;
        }

        if (tokenData.amount == 0 || tokenData.tokenType == TokenType.ERC721) {
            _removeToken(id_);
        }

        payable(tokenData.owner).transfer(msg.value);
        emit TokenPurchased(
            msg.sender,
            tokenData.owner,
            id_,
            amount_,
            msg.value
        );
    }

    function cancelTokenOnSale(uint256 id_, TokenType tokenType_)
        public
        nonReentrant
    {
        TokenData storage tokenData = _tokens[id_];

        require(
            tokenData.isActive,
            "ERC1155Marketplace: Token is not listed for sale"
        );
        require(
            tokenData.owner == msg.sender,
            "ERC1155Marketplace: You do not own this token"
        );

        if (tokenType_ == TokenType.ERC721) {
            try _erc721Contract.ownerOf(id_) {
                _removeToken(id_);
                delete _tokens[id_];
            } catch {
                revert("ERC1155Marketplace: Token doesn't exist");
            }
        } else if (tokenType_ == TokenType.ERC1155) {
            _removeToken(id_);
            delete _tokens[id_];
        }

        emit TokenCanceledFromSale(msg.sender, id_);
    }

    function batchBuyTokens(
        uint256[] calldata ids_,
        uint256[] calldata amounts_
    ) public payable nonReentrant {
        require(
            ids_.length == amounts_.length,
            "ERC1155Marketplace: IDs and amounts length mismatch"
        );

        address tokenOwner = _tokens[ids_[0]].owner;
        require(
            tokenOwner != address(0),
            "ERC1155Marketplace: No tokens to buy"
        );

        uint256 totalPrice = 0;

        for (uint256 i = 0; i < ids_.length; i++) {
            require(
                _tokens[ids_[i]].owner == tokenOwner,
                "ERC1155Marketplace: Tokens must have the same owner"
            );
            require(
                msg.sender != tokenOwner,
                "ERC1155Marketplace: You are the owner"
            );
            require(
                amounts_[i] <= _tokens[ids_[i]].amount,
                "ERC1155Marketplace: Amount exceeds listed amount"
            );

            totalPrice += _tokens[ids_[i]].price * amounts_[i];
        }

        require(
            msg.value >= totalPrice,
            "ERC1155Marketplace: Insufficient Payment"
        );

        _erc1155Contract.safeBatchTransferFrom(
            tokenOwner,
            msg.sender,
            ids_,
            amounts_,
            ""
        );

        for (uint256 i = 0; i < ids_.length; i++) {
            uint256 tokenId = ids_[i];
            _tokens[tokenId].amount -= amounts_[i];
            if (_tokens[tokenId].amount == 0) {
                _removeToken(tokenId);
            }
        }

        payable(tokenOwner).transfer(totalPrice);

        emit TokensPurchased(
            msg.sender,
            tokenOwner,
            ids_,
            amounts_,
            totalPrice
        );
    }

    function _removeToken(uint256 id_) private {
        _tokens[id_].isActive = false;
        for (uint256 i = 0; i < _listedTokens.length; i++) {
            if (_listedTokens[i] == id_) {
                _listedTokens[i] = _listedTokens[_listedTokens.length - 1];
                _listedTokens.pop();
                break;
            }
        }

        for (uint256 i = 0; i < _tokensOnAuction.length; i++) {
            if (_tokensOnAuction[i] == id_) {
                _tokensOnAuction[i] = _tokensOnAuction[
                    _tokensOnAuction.length - 1
                ];
                _tokensOnAuction.pop();
                break;
            }
        }
    }

    function putTokenOnAuction(
        uint256 tokenId_,
        uint256 basePrice_,
        uint256 duration_,
        uint256 amount_,
        TokenType tokenType_
    ) public nonReentrant {
        if (tokenType_ == TokenType.ERC721) {
            require(
                !_auctions[tokenId_].isActive ||
                    _auctions[tokenId_].tokenType != TokenType.ERC721,
                "ERC1155Marketplace: Auction is active for ERC721 token"
            );
        } else {
            require(
                !_auctions[tokenId_].isActive ||
                    _auctions[tokenId_].tokenType != TokenType.ERC1155,
                "ERC1155Marketplace: Auction is active for ERC1155 token"
            );
        }

        require(
            !_auctions[tokenId_].isActive,
            "ERC1155Marketplace: Auction is active for this token"
        );
        require(
            basePrice_ > 0,
            "ERC1155Marketplace: Base price must be greater than 0"
        );
        require(
            duration_ > 0,
            "ERC1155Marketplace: Duration must be greater than 0"
        );

        TokenData storage tokenData = _tokens[tokenId_];

        if (tokenType_ == TokenType.ERC721) {
            require(
                amount_ == 0,
                "ERC1155Marketplace: Amount must be 0 for ERC721 tokens"
            );

            try _erc721Contract.ownerOf(tokenId_) {
                require(
                    !tokenData.isActive,
                    "ERC1155Marketplace: Token already listed for sale"
                );
                require(
                    _erc721Contract.ownerOf(tokenId_) == msg.sender,
                    "ERC1155Marketplace: You do not own this ERC721 token"
                );
                require(
                    _erc721Contract.isApprovedForAll(
                        msg.sender,
                        address(this)
                    ) || _erc721Contract.getApproved(tokenId_) == address(this),
                    "ERC1155Marketplace: Marketplace not approved for ERC721"
                );
                if (tokenData.isActive) {
                    _removeToken(tokenId_);
                }
            } catch {
                revert("ERC1155Marketplace: Token does not exist");
            }
        } else if (tokenType_ == TokenType.ERC1155) {
            require(
                _erc1155Contract.balanceOf(msg.sender, tokenId_) >= amount_,
                "ERC1155Marketplace: Insufficient ERC1155 token balance"
            );

            require(
                _erc1155Contract.isApprovedForAll(msg.sender, address(this)),
                "ERC1155Marketplace: Marketplace not approved for ERC1155"
            );
            if (tokenData.tokenId == 0) {
                revert(
                    "ERC1155Marketplace: Token does not exist or not listed"
                );
            }
            if (tokenData.isActive) {
                _removeToken(tokenId_);
            }
        }

        _auctions[tokenId_] = Auction({
            basePrice: basePrice_,
            seller: msg.sender,
            highestBid: 0,
            highestBidder: address(0),
            startTime: block.timestamp,
            endTime: block.timestamp + duration_,
            amount: amount_,
            tokenType: tokenType_,
            isActive: true
        });

        _tokensOnAuction.push(tokenId_);

        emit TokenListedForAuction(
            msg.sender,
            tokenId_,
            basePrice_,
            duration_,
            amount_,
            tokenType_
        );
    }

    function bidOnAuction(uint256 tokenId_) public payable nonReentrant {
        Auction storage auction = _auctions[tokenId_];

        require(auction.isActive, "ERC1155Marketplace: Auction is not active");
        require(
            block.timestamp >= auction.startTime &&
                block.timestamp <= auction.endTime,
            "ERC1155Marketplace: Auction is not active or has ended"
        );

        uint256 minBid;

        if (auction.tokenType == TokenType.ERC721) {
            require(
                _tokens[tokenId_].price == 0,
                "ERC1155Marketplace: ERC721 token is already listed for sale"
            );
            require(
                auction.amount == 0,
                "ERC1155Marketplace: Amount must be 0 for ERC721 tokens"
            );
            minBid = auction.highestBid == 0
                ? auction.basePrice
                : auction.highestBid;
            require(
                msg.value > minBid,
                "ERC1155Marketplace: Bid must be higher than current highest bid"
            );
        } else if (auction.tokenType == TokenType.ERC1155) {
            require(
                auction.amount > 0,
                "ERC1155Marketplace: Amount must be greater than 0 for ERC1155 tokens"
            );
            require(
                msg.value > auction.basePrice,
                "ERC1155Marketplace: Bid must be higher than base price"
            );
            require(
                msg.value > auction.highestBid,
                "ERC1155Marketplace: Bid must be higher than current highest bid"
            );
        }

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;

        emit NewBid(msg.sender, tokenId_, msg.value);
    }

    function settleAuction(uint256 tokenId_) public nonReentrant {
        Auction storage auction = _auctions[tokenId_];

        require(auction.isActive, "ERC1155Marketplace: Auction is not active");
        require(
            auction.seller == msg.sender,
            "ERC1155Marketplace: Only seller can settle the auction"
        );
        require(
            block.timestamp > auction.endTime,
            "ERC1155Marketplace: Auction has not ended yet"
        );

        auction.isActive = false;

        if (auction.highestBidder != address(0)) {
            if (auction.tokenType == TokenType.ERC721) {
                require(
                    auction.amount == 0,
                    "ERC1155Marketplace: ERC721 auction amount must be 0"
                );
                _erc721Contract.safeTransferFrom(
                    auction.seller,
                    auction.highestBidder,
                    tokenId_
                );
            } else {
                require(
                    auction.amount > 0,
                    "ERC1155Marketplace: ERC1155 auction amount must be greater than 0"
                );
                _erc1155Contract.safeTransferFrom(
                    auction.seller,
                    auction.highestBidder,
                    tokenId_,
                    auction.amount,
                    ""
                );
            }

            payable(auction.seller).transfer(auction.highestBid);

            emit AuctionSettled(
                tokenId_,
                auction.highestBidder,
                auction.highestBid
            );
        } else {
            if (auction.tokenType == TokenType.ERC721) {
                _erc721Contract.safeTransferFrom(
                    address(this),
                    auction.seller,
                    tokenId_
                );
            } else {
                _erc1155Contract.safeTransferFrom(
                    address(this),
                    auction.seller,
                    tokenId_,
                    auction.amount,
                    ""
                );
            }

            emit AuctionSettled(tokenId_, address(0), 0);
        }

        delete _auctions[tokenId_];
    }

    function cancelAuction(uint256 tokenId_) public nonReentrant {
        Auction storage auction = _auctions[tokenId_];

        require(auction.isActive, "ERC1155Marketplace: Auction is not active");

        require(
            auction.seller == msg.sender,
            "ERC1155Marketplace: Only the seller can cancel the auction"
        );

        auction.isActive = false;

        if (auction.tokenType == TokenType.ERC721) {
            if (auction.highestBidder != address(0)) {
                payable(auction.highestBidder).transfer(auction.highestBid);
            }
        } else if (auction.tokenType == TokenType.ERC1155) {
            if (auction.highestBidder != address(0)) {
                payable(auction.highestBidder).transfer(auction.highestBid);
            }
        }

        emit AuctionCanceled(tokenId_, msg.sender);

        delete _auctions[tokenId_];
    }
}
