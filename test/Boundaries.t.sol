// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {Decode} from "./helpers/Decode.sol";
import {NightFrogs} from "../src/NightFrogs.sol";
import {MockCoordinator} from "./helpers/Mocks.sol";
import {IERC721Errors, IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @dev A buyer contract that never implements onERC721Received: safe-minting to it must fail.
contract DeafBuyer {
    function buy(NightFrogs nft, address token, uint256 n) external {
        (bool ok,) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", address(nft), n * nft.price()));
        require(ok);
        nft.mint(n);
    }
}

/// @notice Edge inputs the happy path never reaches: zero, one, the maximum, the same call twice,
/// a caller who is not who the code assumed.
contract BoundariesTest is Fixture {
    using Decode for string;

    event SaleClosed(uint256 finalSupply);

    uint256 internal constant MAX_PRICE_EVEN = (type(uint256).max / 500) - ((type(uint256).max / 500) % 2);

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }

    // ---------------------------------------------------------------- price boundaries

    function testMaximumAllowedPriceMintsTenWithoutOverflow() public {
        vm.prank(owner);
        nft.setPrice(MAX_PRICE_EVEN);
        vm.prank(owner);
        nft.setTreasury(treasury);
        _buy(alice, 10);
        assertEq(nft.totalBurned(), MAX_PRICE_EVEN * 10 / 2);
        assertEq(token.balanceOf(treasury), MAX_PRICE_EVEN * 10 / 2);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), MAX_PRICE_EVEN * 10 / 2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(nft.balanceOf(alice), 10);
    }

    function testPriceJustAboveBoundIsRejectedAndBoundItselfAccepted() public {
        uint256 bound_ = type(uint256).max / 500;
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.InvalidPrice.selector);
        nft.setPrice(bound_ + 1);
        vm.expectRevert(NightFrogs.InvalidPrice.selector);
        nft.setPrice(bound_ + 2);
        nft.setPrice(MAX_PRICE_EVEN);
        assertEq(nft.price(), MAX_PRICE_EVEN);
        nft.setPrice(2); // the smallest price: one unit burned, one unit to treasury
        vm.stopPrank();
        _buy(alice, 1);
        assertEq(nft.totalBurned(), 1);
        assertEq(token.balanceOf(owner), 1);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzSetPriceAcceptsExactlyEvenPositiveBoundedValues(uint256 candidate) public {
        bool valid = candidate != 0 && candidate % 2 == 0 && candidate <= type(uint256).max / 500;
        uint256 before = nft.price();
        vm.prank(owner);
        if (valid) {
            nft.setPrice(candidate);
            assertEq(nft.price(), candidate);
        } else {
            vm.expectRevert(NightFrogs.InvalidPrice.selector);
            nft.setPrice(candidate);
            assertEq(nft.price(), before);
        }
    }

    /// @dev A buyer who approved exactly the quoted cost is not charged a higher price set afterwards.
    function testExactAllowanceProtectsBuyerFromLaterPriceIncrease() public {
        token.fund(alice, 10e18);
        vm.prank(alice);
        token.approve(address(nft), 2e18);
        vm.prank(owner);
        nft.setPrice(4e18);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(nft), 2e18, 4e18)
        );
        nft.mint(1);
        assertEq(token.balanceOf(alice), 10e18);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.totalBurned(), 0);
    }

    // ---------------------------------------------------------------- wallet and supply caps

    /// forge-config: default.fuzz.runs = 256
    function testFuzzTwoMintsRespectLifetimeCap(uint8 rawFirst, uint8 rawSecond) public {
        uint256 first = bound(rawFirst, 1, 10);
        uint256 second = bound(rawSecond, 1, 10);
        _buy(alice, first);
        uint256 cost = second * nft.price();
        token.fund(alice, cost);
        vm.startPrank(alice);
        token.approve(address(nft), cost);
        if (first + second <= 10) {
            nft.mint(second);
            assertEq(nft.mintedBy(alice), first + second);
            assertEq(nft.balanceOf(alice), first + second);
        } else {
            vm.expectRevert(NightFrogs.WalletLimit.selector);
            nft.mint(second);
            assertEq(nft.mintedBy(alice), first);
            assertEq(token.balanceOf(alice), cost);
        }
        vm.stopPrank();
        assertEq(nft.totalBurned(), nft.totalSupply() * nft.price() / 2);
    }

    /// forge-config: default.fuzz.runs = 48
    function testFuzzLastBatchMustFitExactly(uint8 rawLeft, uint8 rawQuantity) public {
        uint256 left = bound(rawLeft, 1, 10);
        uint256 quantity = bound(rawQuantity, 1, 10);
        for (uint256 i; i < 49; ++i) {
            _buy(address(uint160(0x60000 + i)), 10);
        }
        if (left < 10) _buy(bob, 10 - left);
        assertEq(nft.totalSupply(), 500 - left);
        uint256 cost = quantity * nft.price();
        token.fund(alice, cost);
        vm.startPrank(alice);
        token.approve(address(nft), cost);
        if (quantity <= left) {
            nft.mint(quantity);
            assertEq(nft.totalSupply(), 500 - left + quantity);
            assertEq(nft.ownerOf(500 - left + quantity), alice);
        } else {
            vm.expectRevert(NightFrogs.SoldOut.selector);
            nft.mint(quantity);
            assertEq(nft.totalSupply(), 500 - left);
        }
        vm.stopPrank();
        assertLe(nft.totalSupply(), 500);
    }

    function testWalletCapIsPerAddressNotPerTransactionAndNotPerHolding() public {
        for (uint256 i = 1; i <= 10; ++i) {
            _buy(alice, 1); // ten single mints reach exactly ten
        }
        assertEq(nft.mintedBy(alice), 10);
        token.fund(alice, 2e18);
        vm.startPrank(alice);
        token.approve(address(nft), 2e18);
        vm.expectRevert(NightFrogs.WalletLimit.selector);
        nft.mint(1);
        // Giving everything away restores nothing.
        for (uint256 id = 1; id <= 10; ++id) {
            nft.transferFrom(alice, bob, id);
        }
        assertEq(nft.balanceOf(alice), 0);
        vm.expectRevert(NightFrogs.WalletLimit.selector);
        nft.mint(1);
        vm.stopPrank();
        assertEq(nft.balanceOf(bob), 10);
        assertEq(nft.mintedBy(bob), 0);
        _buy(bob, 10); // a receiver's own allowance is untouched by what it was given
        assertEq(nft.balanceOf(bob), 20);
    }

    // ---------------------------------------------------------------- callers the code did not expect

    function testContractWithoutReceiverHookCannotMintAndPaysNothing() public {
        DeafBuyer buyer = new DeafBuyer();
        token.fund(address(buyer), 4e18);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(buyer)));
        buyer.buy(nft, address(token), 2);
        assertEq(token.balanceOf(address(buyer)), 4e18);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), 0);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.mintedBy(address(buyer)), 0);
    }

    function testNoHiddenAdminSurface() public {
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("setBurnShare(uint256)", 0);
        calls[1] = abi.encodeWithSignature("setSplit(uint256,uint256)", 100, 0);
        calls[2] = abi.encodeWithSignature("withdraw()");
        calls[3] = abi.encodeWithSignature("withdrawToken(address,uint256)", address(token), 1);
        calls[4] = abi.encodeWithSignature("setRoyalty(uint96)", 1000);
        calls[5] = abi.encodeWithSignature("setDefaultRoyalty(address,uint96)", alice, 1000);
        calls[6] = abi.encodeWithSignature("setRenderer(address)", alice);
        calls[7] = abi.encodeWithSignature("setBaseURI(string)", "ipfs://x");
        calls[8] = abi.encodeWithSignature("setMaxSupply(uint256)", 1000);
        calls[9] = abi.encodeWithSignature("airdrop(address[],uint256)", new address[](0), 1);
        calls[10] = abi.encodeWithSignature("setCoordinator(address)", alice);
        calls[11] = abi.encodeWithSignature("setRandomWord(uint256)", 7);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(owner);
            (bool ok,) = address(nft).call(calls[i]);
            assertFalse(ok, "unexpected admin function answered");
        }
        assertEq(nft.price(), 2e18);
        assertEq(nft.totalSupply(), 0);
    }

    function testTreasuryBuyerStillBurnsHalf() public {
        vm.prank(owner);
        nft.setTreasury(alice);
        _buy(alice, 4);
        // Alice paid 8 IMD and received 4 back as treasury: the burn is unaffected.
        assertEq(token.balanceOf(alice), 4e18);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), 4e18);
        assertEq(nft.totalBurned(), 4e18);
    }

    function testNothingIsPreMintedAndNoTokenExistsAboveSupply() public {
        assertEq(nft.balanceOf(owner), 0);
        for (uint256 id; id <= 2; ++id) {
            vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
            nft.ownerOf(id);
        }
        _buy(alice, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 4));
        nft.ownerOf(4);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 4));
        nft.tokenURI(4);
    }

    function testStandardTransferFailurePaths() public {
        _buy(alice, 2);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        nft.transferFrom(alice, address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(token)));
        nft.safeTransferFrom(alice, address(token), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, bob, 1, alice));
        nft.transferFrom(bob, alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 3));
        nft.transferFrom(alice, bob, 3);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, bob, 2));
        nft.transferFrom(alice, bob, 2);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), alice);
    }

    // ---------------------------------------------------------------- reveal edges

    function testRevealRefusedWhenCoordinatorHasNoCode() public {
        address bareCoordinator = makeAddr("coordinator without code");
        NightFrogs bare = new NightFrogs(owner, bareCoordinator, address(renderer));
        for (uint256 i; i < 50; ++i) {
            address buyer = address(uint160(0x70000 + i));
            token.fund(buyer, 20e18);
            vm.startPrank(buyer);
            token.approve(address(bare), 20e18);
            bare.mint(10);
            vm.stopPrank();
        }
        assertEq(bare.totalSupply(), 500);
        vm.startPrank(owner);
        bare.configureVRF(42, TEST_KEY);
        vm.expectRevert(NightFrogs.VRFNotConfigured.selector);
        bare.reveal();
        vm.stopPrank();
        assertFalse(bare.revealRequested());
        // Giving the address code afterwards makes the same request succeed: nothing was consumed.
        vm.etch(bareCoordinator, address(coordinator).code);
        vm.prank(owner);
        uint256 id = bare.reveal();
        assertEq(id, 1);
        assertTrue(bare.revealRequested());
    }

    /// forge-config: default.fuzz.runs = 128
    function testFuzzFulfillmentRejectsEveryWrongShape(uint256 requestId, uint8 rawLength, address caller)
        public
    {
        _sellOut();
        uint256 expected = _request();
        uint256 length = bound(rawLength, 0, 4);
        uint256[] memory words = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            words[i] = uint256(keccak256(abi.encode(requestId, i)));
        }
        if (caller != address(coordinator)) {
            vm.prank(caller);
            vm.expectRevert(NightFrogs.OnlyCoordinator.selector);
            nft.rawFulfillRandomWords(requestId, words);
        }
        if (requestId != expected || length != 1) {
            vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
            coordinator.fulfill(nft, requestId, words);
            assertFalse(nft.revealed());
            assertEq(nft.randomWord(), 0);
        } else {
            coordinator.fulfill(nft, requestId, words);
            assertTrue(nft.revealed());
            assertEq(nft.randomWord(), words[0]);
        }
        // Whatever happened, the request stays recorded and a second request is impossible.
        assertTrue(nft.revealRequested());
        assertEq(nft.revealRequestId(), expected);
        vm.prank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
    }

    /// @dev The request one frog short of sellout freezes the supply at 499: the last frog is never sold,
    /// not to a fresh wallet, not with a cost ceiling, and not after the word lands.
    function testRevealOneShortOfSelloutFreezesSupplyAtFourNinetyNine() public {
        for (uint256 i; i < 49; ++i) {
            _buy(address(uint160(0x80000 + i)), 10);
        }
        _buy(alice, 9);
        assertEq(nft.totalSupply(), 499);
        assertFalse(nft.revealRequestStale()); // nothing requested yet: never stale
        vm.startPrank(owner);
        nft.configureVRF(42, TEST_KEY);
        vm.expectEmit(false, false, false, true, address(nft));
        emit SaleClosed(499);
        nft.reveal();
        vm.stopPrank();
        assertTrue(nft.revealRequested());
        token.fund(bob, 2e18);
        vm.startPrank(bob);
        token.approve(address(nft), 2e18);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1, 2e18);
        vm.stopPrank();
        _fulfill(99);
        vm.prank(bob);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1);
        assertEq(nft.totalSupply(), 499);
        assertEq(token.balanceOf(bob), 2e18);
        assertEq(nft.totalBurned(), 499e18);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 500));
        nft.ownerOf(500);
    }

    /// @dev A single minted frog is enough to request; an empty collection is not.
    function testRevealNeedsExactlyOneFrog() public {
        vm.startPrank(owner);
        nft.configureVRF(42, TEST_KEY);
        vm.expectRevert(NightFrogs.NothingMinted.selector);
        nft.reveal();
        vm.stopPrank();
        assertFalse(nft.revealRequested());
        assertEq(coordinator.requests(), 0);
        _buy(alice, 1);
        vm.expectEmit(false, false, false, true, address(nft));
        emit SaleClosed(1);
        vm.prank(owner);
        nft.reveal();
        assertTrue(nft.revealRequested());
        _fulfill(5);
        assertEq(nft.tokenURI(1), renderer.tokenURI(1, true, 5));
    }

    /// @dev The order of checks: a closed sale is reported before supply, wallet and cost problems, but
    /// an invalid quantity is reported first of all.
    function testClosedSaleErrorOrdering() public {
        _buy(alice, 10);
        _request();
        token.fund(alice, 20e18);
        vm.startPrank(alice);
        token.approve(address(nft), 20e18);
        vm.expectRevert(NightFrogs.InvalidQuantity.selector);
        nft.mint(0);
        vm.expectRevert(NightFrogs.InvalidQuantity.selector);
        nft.mint(11, 0);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1); // alice is at her wallet cap: MintClosed still wins
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1, 0); // and over the cost ceiling
        vm.stopPrank();
        assertEq(nft.mintedBy(alice), 10);
    }

    /// forge-config: default.fuzz.runs = 256
    /// @dev The ceiling is inclusive: a ceiling equal to the cost pays, one unit less reverts with the
    /// exact cost in the error, and nothing moves on a revert.
    function testFuzzCostCeilingIsInclusiveAndAtomic(uint8 rawQuantity, uint256 rawPrice, uint256 rawCeiling)
        public
    {
        uint256 quantity = bound(rawQuantity, 1, 10);
        uint256 unitPrice = bound(rawPrice, 1, 1e24) * 2;
        vm.prank(owner);
        nft.setPrice(unitPrice);
        uint256 cost = unitPrice * quantity;
        uint256 ceiling = bound(rawCeiling, 0, cost * 2);
        token.fund(alice, cost);
        vm.startPrank(alice);
        token.approve(address(nft), cost);
        if (ceiling >= cost) {
            nft.mint(quantity, ceiling);
            assertEq(nft.balanceOf(alice), quantity);
            assertEq(token.balanceOf(alice), 0);
            assertEq(nft.totalBurned(), cost / 2);
        } else {
            vm.expectRevert(abi.encodeWithSelector(NightFrogs.CostAboveLimit.selector, cost, ceiling));
            nft.mint(quantity, ceiling);
            assertEq(nft.balanceOf(alice), 0);
            assertEq(nft.mintedBy(alice), 0);
            assertEq(token.balanceOf(alice), cost);
            assertEq(token.allowance(alice, address(nft)), cost);
            assertEq(nft.totalBurned(), 0);
            assertEq(nft.totalSupply(), 0);
        }
        vm.stopPrank();
    }

    /// @dev A ceiling of exactly the quoted total buys at the quoted price even if the owner lowers the
    /// price first: the buyer is only ever charged the execution-time price.
    function testCostCeilingAllowsCheaperExecution() public {
        token.fund(alice, 20e18);
        vm.prank(alice);
        token.approve(address(nft), 20e18);
        vm.prank(owner);
        nft.setPrice(1e18);
        vm.prank(alice);
        nft.mint(10, 20e18);
        assertEq(token.balanceOf(alice), 10e18);
        assertEq(nft.totalBurned(), 5e18);
        assertEq(nft.balanceOf(alice), 10);
    }

    /// @dev Replacing a stale request never reopens the sale, keeps the frozen supply, and the
    /// abandoned id is dead even if it arrives after the replacement has already revealed.
    function testStaleReplacementKeepsSaleClosedAndSupplyFrozen() public {
        _buy(alice, 3);
        uint256 requestedAt = 1_800_000_000;
        vm.warp(requestedAt);
        uint256 firstId = _request();
        vm.warp(requestedAt + nft.REVEAL_RETRY_DELAY());
        vm.prank(owner);
        uint256 secondId = nft.reveal();
        assertEq(secondId, firstId + 1);
        assertTrue(nft.revealRequested());
        assertEq(nft.totalSupply(), 3);
        token.fund(bob, 2e18);
        vm.startPrank(bob);
        token.approve(address(nft), 2e18);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1);
        vm.stopPrank();
        // The replacement itself goes stale again if nothing arrives: a third request is possible.
        vm.warp(block.timestamp + nft.REVEAL_RETRY_DELAY() - 1);
        vm.prank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
        vm.warp(block.timestamp + 1);
        vm.prank(owner);
        uint256 thirdId = nft.reveal();
        assertEq(thirdId, secondId + 1);
        assertEq(coordinator.requests(), 3);
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, firstId, words);
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, secondId, words);
        _fulfill(2);
        assertEq(nft.randomWord(), 2);
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, firstId, words);
        assertEq(nft.randomWord(), 2);
        assertEq(nft.totalSupply(), 3);
    }

    /// @dev During the stale window the owner may fix the configuration, but zero values stay refused
    /// and the new values are what the replacement request carries.
    function testStaleWindowReconfigurationStillValidated() public {
        _buy(alice, 1);
        uint256 requestedAt = 1_800_000_000;
        vm.warp(requestedAt);
        _request();
        vm.warp(requestedAt + nft.REVEAL_RETRY_DELAY());
        bytes32 otherKey = keccak256("corrected gas lane");
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.VRFNotConfigured.selector);
        nft.configureVRF(0, otherKey);
        vm.expectRevert(NightFrogs.VRFNotConfigured.selector);
        nft.configureVRF(77, bytes32(0));
        nft.configureVRF(77, otherKey);
        nft.reveal();
        vm.stopPrank();
        assertEq(coordinator.lastSub(), 77);
        assertEq(coordinator.lastKey(), otherKey);
        assertEq(nft.revealRequestedAt(), requestedAt + nft.REVEAL_RETRY_DELAY());
        assertFalse(nft.revealRequestStale());
    }

    function testNewOwnerAfterHandoverControlsRevealAndRoyalties() public {
        _sellOut();
        vm.prank(owner);
        nft.transferOwnership(bob);
        // Until acceptance the old owner still acts.
        vm.prank(owner);
        nft.configureVRF(7, TEST_KEY);
        vm.prank(bob);
        nft.acceptOwnership();
        vm.prank(owner);
        vm.expectRevert();
        nft.reveal();
        vm.prank(bob);
        nft.reveal();
        (address recipient,) = nft.royaltyInfo(1, 1 ether);
        assertEq(recipient, bob);
        assertEq(nft.treasury(), owner);
    }

    // ---------------------------------------------------------------- royalties

    /// forge-config: default.fuzz.runs = 512
    function testFuzzRoyaltyIsFivePercentRoundedDownForAnyPriceAndToken(uint256 tokenId, uint256 salePrice)
        public
        view
    {
        (address recipient, uint256 amount) = nft.royaltyInfo(tokenId, salePrice);
        assertEq(recipient, owner);
        assertEq(amount, salePrice / 20);
        assertLe(amount, salePrice);
    }

    function testRoyaltyEdges() public view {
        (, uint256 zero) = nft.royaltyInfo(1, 0);
        assertEq(zero, 0);
        (, uint256 tiny) = nft.royaltyInfo(1, 19);
        assertEq(tiny, 0);
        (, uint256 one) = nft.royaltyInfo(1, 20);
        assertEq(one, 1);
        (, uint256 max) = nft.royaltyInfo(500, type(uint256).max);
        assertEq(max, type(uint256).max / 20);
    }

    // ---------------------------------------------------------------- metadata at the boundaries

    function testPlaceholderIsIdenticalInShapeForFirstAndLastTokenAndChangesOnlyAtReveal() public {
        _sellOut();
        string memory first = nft.tokenURI(1).dataURI("data:application/json;base64,");
        string memory last = nft.tokenURI(500).dataURI("data:application/json;base64,");
        assertEq(vm.parseJsonString(first, ".name"), "NIGHT FROGS #1");
        assertEq(vm.parseJsonString(last, ".name"), "NIGHT FROGS #500");
        assertEq(vm.parseJsonString(last, ".attributes[0].trait_type"), "Status");
        assertEq(nft.tokenURI(500), renderer.tokenURI(500, false, 0));
        _request();
        assertEq(nft.tokenURI(500), renderer.tokenURI(500, false, 0)); // requesting alone reveals nothing
        _fulfill(777);
        assertEq(nft.tokenURI(500), renderer.tokenURI(500, true, 777));
        assertNotEq(nft.tokenURI(500), renderer.tokenURI(500, false, 0));
    }

    function testGenesisBoundaryAt77And78() public {
        _sellOut();
        _request();
        _fulfill(31337);
        string memory g = nft.tokenURI(77).dataURI("data:application/json;base64,");
        string memory n = nft.tokenURI(78).dataURI("data:application/json;base64,");
        assertEq(vm.parseJsonString(g, ".attributes[0].value"), "Genesis Sunburst");
        assertEq(vm.parseJsonString(g, ".attributes[7].value"), "Genesis");
        assertEq(vm.parseJsonString(g, ".attributes[8].value"), "Crew Issue"); // only #1 is the captain
        assertNotEq(vm.parseJsonString(n, ".attributes[0].value"), "Genesis Sunburst");
        assertEq(vm.parseJsonString(n, ".attributes[7].value"), "Night Crew");
        string memory genesisSVG = vm.parseJsonString(g, ".image").dataURI("data:image/svg+xml;base64,");
        string memory crewSVG = vm.parseJsonString(n, ".image").dataURI("data:image/svg+xml;base64,");
        assertTrue(_contains(genesisSVG, "GENESIS"));
        assertFalse(_contains(crewSVG, "GENESIS"));
        assertFalse(_contains(genesisSVG, "NO SLEEP")); // captain-only overlay
        assertTrue(_contains(genesisSVG, "#77</text>"));
        assertTrue(_contains(crewSVG, "#78</text>"));
    }

    function testEveryRevealedTokenURIHasNineAttributesAndMatchesTraits() public {
        _sellOut();
        _request();
        _fulfill(424242);
        uint16[8] memory ids = [1, 2, 76, 77, 78, 250, 499, 500];
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            string memory json = nft.tokenURI(id).dataURI("data:application/json;base64,");
            uint8[7] memory selected = renderer.traits(id, 424242);
            for (uint8 layer; layer < 7; ++layer) {
                string memory prefix = string.concat(".attributes[", vm.toString(layer), "].value");
                assertEq(vm.parseJsonString(json, prefix), renderer.traitName(layer, selected[layer]));
            }
            assertEq(vm.parseJsonString(json, ".attributes[7].trait_type"), "Edition");
            assertEq(vm.parseJsonString(json, ".attributes[8].trait_type"), "Signature");
            assertTrue(vm.keyExistsJson(json, ".attributes[8]"));
            assertFalse(vm.keyExistsJson(json, ".attributes[9]"), "extra attribute present");
        }
    }
}
