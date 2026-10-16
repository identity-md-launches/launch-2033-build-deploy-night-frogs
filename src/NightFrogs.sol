// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVRFCoordinatorV2Plus} from "./interfaces/IVRFCoordinatorV2Plus.sol";

interface IFrogRenderer {
    function tokenURI(uint256 tokenId, bool revealed, uint256 randomWord)
        external
        view
        returns (string memory);
}

/// @title NIGHT FROGS — the 3 AM crew of NIGHTSHIFT.
/// @notice Up to 500 paid mints. Immutable art, payment token, 50/50 split and royalty rate.
///         The owner's reveal request ends the sale; the supply never grows afterwards.
contract NightFrogs is ERC721, Ownable2Step, ReentrancyGuard, IERC2981 {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 500;
    uint256 public constant GENESIS_SUPPLY = 77;
    uint256 public constant MAX_PER_WALLET = 10;
    uint96 public constant ROYALTY_BPS = 500;
    address public constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint32 public constant CALLBACK_GAS_LIMIT = 120_000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    /// @dev A request still unfulfilled this long after it was made is treated as abandoned by
    /// Chainlink (wrong key hash, unfunded subscription, failed callback) and may be replaced.
    uint256 public constant REVEAL_RETRY_DELAY = 3 days;
    bytes4 private constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));

    address public immutable coordinator;
    IFrogRenderer public immutable renderer;
    address public treasury;
    uint256 public price = 2 ether; // IMD has 18 decimals; checked on first use, not in constructor.
    uint256 public totalSupply;
    uint256 public totalBurned;
    mapping(address => uint256) public mintedBy;

    uint256 public subscriptionId;
    bytes32 public keyHash;
    uint256 public revealRequestId;
    uint256 public revealRequestedAt;
    bool public revealRequested;
    bool public revealed;
    uint256 public randomWord;

    event PriceChanged(uint256 previousPrice, uint256 newPrice);
    event TreasuryChanged(address indexed previousTreasury, address indexed newTreasury);
    event Burned(address indexed payer, uint256 amount, uint256 cumulativeBurned);
    event Minted(address indexed payer, uint256 firstTokenId, uint256 quantity, uint256 paid);
    event VRFConfigured(uint256 subscriptionId, bytes32 keyHash);
    /// @dev The first reveal request ends the sale for good at the supply minted so far.
    event SaleClosed(uint256 finalSupply);
    event RevealRequested(uint256 indexed requestId);
    /// @dev A stale request was replaced; a fulfillment for it is no longer accepted.
    event RevealRequestAbandoned(uint256 indexed requestId);
    event Revealed(uint256 indexed requestId, uint256 randomWord);
    /// @dev ERC-4906 refresh for all minted metadata after fulfillment.
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    error InvalidAddress();
    error InvalidPrice();
    error InvalidQuantity();
    error WalletLimit();
    error SoldOut();
    error MintClosed();
    error CostAboveLimit(uint256 cost, uint256 maxTotalCost);
    error PaymentNotConfigured();
    error InexactPayment();
    error VRFNotConfigured();
    error RevealAlreadyRequested();
    error NothingMinted();
    error OnlyCoordinator();
    error InvalidFulfillment();
    error OwnershipRequired();

    constructor(address owner_, address coordinator_, address renderer_)
        ERC721("NIGHT FROGS", "NFROG")
        Ownable(owner_)
    {
        if (
            owner_ == BURN_ADDRESS || owner_ == address(this) || coordinator_ == address(0)
                || renderer_ == address(0)
        ) revert InvalidAddress();
        treasury = owner_;
        coordinator = coordinator_;
        renderer = IFrogRenderer(renderer_);
    }

    /// @notice Quantity is lifetime mints by the caller; transfers never restore mint allowance.
    /// @dev Charges the price in storage at execution time. Approve exactly `quantity * price()`
    ///      or use the overload with a cost ceiling to be protected from a price change mined first.
    function mint(uint256 quantity) external nonReentrant {
        _purchase(quantity, type(uint256).max);
    }

    /// @notice Same as `mint(quantity)` but reverts if `price * quantity` exceeds `maxTotalCost`.
    function mint(uint256 quantity, uint256 maxTotalCost) external nonReentrant {
        _purchase(quantity, maxTotalCost);
    }

    function _purchase(uint256 quantity, uint256 maxTotalCost) private {
        if (quantity == 0 || quantity > MAX_PER_WALLET) revert InvalidQuantity();
        if (revealRequested) revert MintClosed();
        uint256 first = totalSupply + 1;
        if (totalSupply + quantity > MAX_SUPPLY) revert SoldOut();
        if (mintedBy[msg.sender] + quantity > MAX_PER_WALLET) revert WalletLimit();
        if (IMD.code.length == 0 || IERC20Metadata(IMD).decimals() != 18) revert PaymentNotConfigured();

        uint256 cost = price * quantity;
        if (cost > maxTotalCost) revert CostAboveLimit(cost, maxTotalCost);
        uint256 half = cost / 2;
        address recipient = treasury;
        totalSupply += quantity;
        mintedBy[msg.sender] += quantity;
        totalBurned += half;

        IERC20 token = IERC20(IMD);
        uint256 held = token.balanceOf(address(this));
        uint256 payerBefore = token.balanceOf(msg.sender);
        token.safeTransferFrom(msg.sender, address(this), cost);
        if (
            token.balanceOf(address(this)) != held + cost || payerBefore < cost
                || token.balanceOf(msg.sender) != payerBefore - cost
        ) revert InexactPayment();
        uint256 burnedBefore = token.balanceOf(BURN_ADDRESS);
        token.safeTransfer(BURN_ADDRESS, half);
        if (token.balanceOf(BURN_ADDRESS) != burnedBefore + half) revert InexactPayment();
        uint256 treasuryBefore = token.balanceOf(recipient);
        token.safeTransfer(recipient, half);
        if (token.balanceOf(recipient) != treasuryBefore + half || token.balanceOf(address(this)) != held) {
            revert InexactPayment();
        }
        emit Burned(msg.sender, half, totalBurned);
        for (uint256 i; i < quantity; ++i) {
            _safeMint(msg.sender, first + i);
        }
        emit Minted(msg.sender, first, quantity, cost);
    }

    /// @notice Even smallest-unit amounts preserve the exact split, including single mints.
    function setPrice(uint256 newPrice) external onlyOwner {
        if (newPrice == 0 || newPrice % 2 != 0 || newPrice > type(uint256).max / MAX_SUPPLY) {
            revert InvalidPrice();
        }
        emit PriceChanged(price, newPrice);
        price = newPrice;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0) || newTreasury == BURN_ADDRESS || newTreasury == address(this)) {
            revert InvalidAddress();
        }
        emit TreasuryChanged(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice True while the recorded request is unfulfilled and older than `REVEAL_RETRY_DELAY`.
    function revealRequestStale() public view returns (bool) {
        return revealRequested && !revealed && block.timestamp >= revealRequestedAt + REVEAL_RETRY_DELAY;
    }

    /// @notice Configure a funded Ethereum VRF v2.5 LINK subscription with this consumer registered.
    /// @dev Locked from a request until fulfillment; reopens only once that request is stale, so a
    ///      mistyped key hash or a replaced subscription can be corrected before requesting again.
    function configureVRF(uint256 subscriptionId_, bytes32 keyHash_) external onlyOwner {
        if (revealRequested && !revealRequestStale()) revert RevealAlreadyRequested();
        if (subscriptionId_ == 0 || keyHash_ == bytes32(0)) revert VRFNotConfigured();
        subscriptionId = subscriptionId_;
        keyHash = keyHash_;
        emit VRFConfigured(subscriptionId_, keyHash_);
    }

    /// @notice Requests the one random word. The first call closes minting for good at the
    ///         current supply, so nobody can buy selectively once the seed is known. It can only be
    ///         called again to replace a request that stayed unfulfilled for `REVEAL_RETRY_DELAY`;
    ///         once fulfilled, the reveal is final and no further request is possible.
    function reveal() external onlyOwner nonReentrant returns (uint256 requestId) {
        if (revealRequested && !revealRequestStale()) revert RevealAlreadyRequested();
        if (subscriptionId == 0 || keyHash == bytes32(0) || coordinator.code.length == 0) {
            revert VRFNotConfigured();
        }
        if (totalSupply == 0) revert NothingMinted();
        if (revealRequested) {
            emit RevealRequestAbandoned(revealRequestId);
        } else {
            revealRequested = true;
            emit SaleClosed(totalSupply);
        }
        revealRequestedAt = block.timestamp;
        requestId = IVRFCoordinatorV2Plus(coordinator)
            .requestRandomWords(
                IVRFCoordinatorV2Plus.RandomWordsRequest({
                    keyHash: keyHash,
                    subId: subscriptionId,
                    requestConfirmations: REQUEST_CONFIRMATIONS,
                    callbackGasLimit: CALLBACK_GAS_LIMIT,
                    numWords: 1,
                    extraArgs: abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, false)
                })
            );
        revealRequestId = requestId;
        emit RevealRequested(requestId);
    }

    /// @dev The coordinator verifies the proof. Zero is a valid word. No external calls in callback.
    ///      Only the latest recorded request is accepted, exactly once; a late fulfillment of a
    ///      request the owner has already replaced is rejected.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata words) external {
        if (msg.sender != coordinator) revert OnlyCoordinator();
        if (!revealRequested || revealed || requestId != revealRequestId || words.length != 1) {
            revert InvalidFulfillment();
        }
        randomWord = words[0];
        revealed = true;
        emit Revealed(requestId, words[0]);
        emit BatchMetadataUpdate(1, totalSupply);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return renderer.tokenURI(tokenId, revealed, randomWord);
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        return (owner(), Math.mulDiv(salePrice, ROYALTY_BPS, 10_000));
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || interfaceId == 0x49064906
            || super.supportsInterface(interfaceId);
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == address(0) || newOwner == BURN_ADDRESS || newOwner == address(this)) {
            revert InvalidAddress();
        }
        super.transferOwnership(newOwner);
    }

    /// @notice Royalties and the one-time reveal always need an accountable owner.
    function renounceOwnership() public view override onlyOwner {
        revert OwnershipRequired();
    }
}
