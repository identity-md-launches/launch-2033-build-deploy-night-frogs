// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {NightFrogs} from "../src/NightFrogs.sol";

contract RevealTest is Fixture {
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

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
        vm.expectRevert(NightFrogs.CollectionNotSoldOut.selector);
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
