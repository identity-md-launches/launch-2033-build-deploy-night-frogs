// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {NightFrogs} from "../src/NightFrogs.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract RevealTest is Fixture {
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event SaleClosed(uint256 finalSupply);
    event RevealRequested(uint256 indexed requestId);
    event RevealRequestAbandoned(uint256 indexed requestId);

    function testConfigurationRequiredAndValidated() public {
        assertEq(nft.subscriptionId(), 0);
        assertEq(nft.keyHash(), bytes32(0));
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.VRFNotConfigured.selector);
        nft.reveal();
        vm.expectRevert(NightFrogs.VRFNotConfigured.selector);
        nft.configureVRF(0, TEST_KEY);
        vm.expectRevert(NightFrogs.VRFNotConfigured.selector);
        nft.configureVRF(42, bytes32(0));
        nft.configureVRF(42, TEST_KEY);
        assertEq(nft.subscriptionId(), 42);
        assertEq(nft.keyHash(), TEST_KEY);
        vm.expectRevert(NightFrogs.NothingMinted.selector);
        nft.reveal();
        nft.configureVRF(43, keccak256("another local gas lane"));
        assertEq(nft.subscriptionId(), 43);
        vm.stopPrank();
        assertFalse(nft.revealRequested());
    }

    function testSelloutOneRequestUsesExactV25ABI() public {
        _sellOut();
        uint256 id = _request();
        assertEq(id, 1);
        assertTrue(nft.revealRequested());
        assertFalse(nft.revealed());
        assertEq(coordinator.consumer(), address(nft));
        assertEq(coordinator.lastSub(), 42);
        assertEq(coordinator.lastKey(), TEST_KEY);
        assertEq(coordinator.lastConfirmations(), 3);
        assertEq(coordinator.lastGas(), 120_000);
        assertEq(coordinator.lastWords(), 1);
        // Published Chainlink VRFV2PlusClient EXTRA_ARGS_V1_TAG + ABI false (LINK billing).
        assertEq(coordinator.lastExtra(), abi.encodePacked(hex"92fd1338", uint256(0)));
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.configureVRF(99, TEST_KEY);
        vm.stopPrank();
        assertEq(coordinator.requests(), 1);
    }

    function testRequestFailureIsAtomicAndCanBeRetried() public {
        _sellOut();
        coordinator.setFail(true);
        vm.startPrank(owner);
        nft.configureVRF(42, TEST_KEY);
        vm.expectRevert("subscription unfunded or consumer unregistered");
        nft.reveal();
        vm.stopPrank();
        assertFalse(nft.revealRequested());
        assertFalse(nft.revealed());
        assertEq(nft.revealRequestId(), 0);
        coordinator.setFail(false);
        vm.prank(owner);
        nft.reveal();
        assertEq(coordinator.requests(), 1);
        _fulfill(123);
        assertTrue(nft.revealed());
    }

    function testOnlyExpectedCoordinatorRequestCanFulfill() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 88;
        vm.expectRevert(NightFrogs.OnlyCoordinator.selector);
        nft.rawFulfillRandomWords(1, words);
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, 0, words);
        _sellOut();
        _request();
        vm.prank(owner);
        vm.expectRevert(NightFrogs.OnlyCoordinator.selector);
        nft.rawFulfillRandomWords(1, words);
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, 2, words);
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, 1, new uint256[](0));
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, 1, new uint256[](2));
        assertFalse(nft.revealed());
        assertEq(nft.randomWord(), 0);
        coordinator.fulfill(nft, 1, words);
        assertEq(nft.randomWord(), 88);
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, 1, words);
    }

    function testZeroWordValidImmutableAndEmitsMetadataRefresh() public {
        _sellOut();
        _request();
        vm.expectEmit(false, false, false, true, address(nft));
        emit BatchMetadataUpdate(1, 500);
        _fulfill(0);
        assertTrue(nft.revealed());
        assertEq(nft.randomWord(), 0);
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.configureVRF(42, TEST_KEY);
        vm.stopPrank();
        uint256[] memory moreWords = new uint256[](1);
        moreWords[0] = 999;
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, 1, moreWords);
        assertEq(nft.randomWord(), 0);
    }

    function testCallbackFitsDeclaredGasBudgetAndMakesNoRendererCall() public {
        _sellOut();
        _request();
        // Callback must not depend on the renderer's availability, size or runtime cost.
        vm.etch(address(renderer), hex"60006000fd");
        vm.cool(address(nft));
        (bool success, uint256 used) = coordinator.fulfillWithBudget(nft, 1, type(uint256).max, 120_000);
        assertTrue(success);
        assertLt(used, 120_000);
        assertEq(nft.randomWord(), type(uint256).max);
    }

    function testRevealBeforeSelloutClosesMintAtCurrentSupplyForever() public {
        for (uint256 i; i < 30; ++i) {
            _buy(address(uint160(0x10000 + i)), 10);
        }
        _buy(alice, 7);
        assertEq(nft.totalSupply(), 307);
        vm.startPrank(owner);
        nft.configureVRF(42, TEST_KEY);
        vm.expectEmit(false, false, false, true, address(nft));
        emit SaleClosed(307);
        uint256 id = nft.reveal();
        vm.stopPrank();
        assertEq(id, 1);
        assertTrue(nft.revealRequested());
        // Nobody can buy once the request is out, not even the owner, and not after fulfillment.
        token.fund(bob, 2e18);
        vm.startPrank(bob);
        token.approve(address(nft), 2e18);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1, 2e18);
        vm.stopPrank();
        token.fund(owner, 2e18);
        vm.startPrank(owner);
        token.approve(address(nft), 2e18);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1);
        vm.stopPrank();
        vm.expectEmit(false, false, false, true, address(nft));
        emit BatchMetadataUpdate(1, 307);
        _fulfill(777);
        assertTrue(nft.revealed());
        vm.prank(bob);
        vm.expectRevert(NightFrogs.MintClosed.selector);
        nft.mint(1);
        assertEq(nft.totalSupply(), 307);
        assertEq(nft.totalBurned(), 307e18);
        assertEq(token.balanceOf(bob), 2e18);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 308));
        nft.tokenURI(308);
        // Every minted token renders from the stored word; the placeholder is gone.
        assertTrue(bytes(nft.tokenURI(307)).length > 0);
        assertTrue(keccak256(bytes(nft.tokenURI(1))) != keccak256(bytes(nft.tokenURI(2))));
    }

    function testStaleUnfulfilledRequestCanBeReplacedOnlyAfterDelay() public {
        _sellOut();
        // Explicit anchor: via-IR may re-read block.timestamp after a warp, so never cache it.
        uint256 requestedAt = 1_700_000_000;
        vm.warp(requestedAt);
        vm.startPrank(owner);
        nft.configureVRF(42, keccak256("mistyped gas lane"));
        uint256 firstId = nft.reveal();
        vm.stopPrank();
        assertEq(firstId, 1);
        assertEq(nft.revealRequestedAt(), requestedAt);
        assertEq(nft.REVEAL_RETRY_DELAY(), 3 days);
        assertFalse(nft.revealRequestStale());

        // One second short of the delay: still locked, configuration included.
        vm.warp(requestedAt + nft.REVEAL_RETRY_DELAY() - 1);
        assertFalse(nft.revealRequestStale());
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.configureVRF(42, TEST_KEY);
        vm.stopPrank();

        // At the delay the owner can correct the configuration and request again.
        vm.warp(requestedAt + nft.REVEAL_RETRY_DELAY());
        assertTrue(nft.revealRequestStale());
        vm.startPrank(owner);
        nft.configureVRF(42, TEST_KEY);
        vm.expectEmit(true, false, false, true, address(nft));
        emit RevealRequestAbandoned(1);
        vm.expectEmit(true, false, false, true, address(nft));
        emit RevealRequested(2);
        uint256 secondId = nft.reveal();
        vm.stopPrank();
        assertEq(secondId, 2);
        assertEq(nft.revealRequestId(), 2);
        assertEq(nft.revealRequestedAt(), requestedAt + nft.REVEAL_RETRY_DELAY());
        assertEq(coordinator.lastKey(), TEST_KEY);
        assertFalse(nft.revealRequestStale());
        assertTrue(nft.revealRequested());
        assertFalse(nft.revealed());

        // The abandoned request can no longer reveal; the replacement can, exactly once.
        uint256[] memory words = new uint256[](1);
        words[0] = 11;
        vm.expectRevert(NightFrogs.InvalidFulfillment.selector);
        coordinator.fulfill(nft, 1, words);
        assertFalse(nft.revealed());
        _fulfill(22);
        assertTrue(nft.revealed());
        assertEq(nft.randomWord(), 22);
        assertFalse(nft.revealRequestStale());
        vm.warp(block.timestamp + 365 days);
        assertFalse(nft.revealRequestStale());
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.configureVRF(42, TEST_KEY);
        vm.stopPrank();
        assertEq(coordinator.requests(), 2);
    }

    function testLateFulfillmentOfStaleRequestStillRevealsUntilReplaced() public {
        _sellOut();
        _request();
        vm.warp(block.timestamp + nft.REVEAL_RETRY_DELAY() + 30 days);
        assertTrue(nft.revealRequestStale());
        _fulfill(5);
        assertTrue(nft.revealed());
        assertEq(nft.randomWord(), 5);
        vm.prank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
    }

    function testReplacementRequestFailureKeepsPreviousRequestLive() public {
        _sellOut();
        _request();
        vm.warp(block.timestamp + nft.REVEAL_RETRY_DELAY());
        coordinator.setFail(true);
        vm.prank(owner);
        vm.expectRevert("subscription unfunded or consumer unregistered");
        nft.reveal();
        assertEq(nft.revealRequestId(), 1);
        assertTrue(nft.revealRequestStale());
        coordinator.setFail(false);
        _fulfill(9);
        assertTrue(nft.revealed());
    }

    function testFuzzReplacementNeverBeforeDelayAndNeverAfterReveal(uint64 elapsed, uint256 word) public {
        _sellOut();
        uint256 requestedAt = 1_700_000_000;
        vm.warp(requestedAt);
        _request();
        vm.warp(requestedAt + elapsed);
        bool stale = elapsed >= nft.REVEAL_RETRY_DELAY();
        assertEq(nft.revealRequestStale(), stale);
        if (!stale) {
            vm.prank(owner);
            vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
            nft.reveal();
        } else {
            vm.prank(owner);
            assertEq(nft.reveal(), 2);
        }
        _fulfill(word);
        assertTrue(nft.revealed());
        assertEq(nft.randomWord(), word);
        vm.warp(block.timestamp + 10 * 365 days);
        assertFalse(nft.revealRequestStale());
        vm.prank(owner);
        vm.expectRevert(NightFrogs.RevealAlreadyRequested.selector);
        nft.reveal();
    }

    function testTransfersRemainStandardBeforeDuringAndAfterReveal() public {
        _sellOut();
        address firstBuyer = nft.ownerOf(1);
        vm.prank(firstBuyer);
        nft.transferFrom(firstBuyer, alice, 1);
        _request();
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        _fulfill(123456);
        vm.prank(bob);
        nft.transferFrom(bob, alice, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.totalBurned(), 500e18);
    }
}
