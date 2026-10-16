// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {NightFrogs} from "../src/NightFrogs.sol";
import {MockIMD, MintReceiver} from "./helpers/Mocks.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Errors, IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NightFrogsTest is Fixture {
    event Burned(address indexed payer, uint256 amount, uint256 cumulativeBurned);
    event Minted(address indexed payer, uint256 firstTokenId, uint256 quantity, uint256 paid);

    function testFactoryDeploymentStartsEmptyWithExplicitOwner() public view {
        assertEq(nft.owner(), owner);
        assertTrue(nft.owner() != address(this));
        assertEq(nft.treasury(), owner);
        assertEq(nft.name(), "NIGHT FROGS");
        assertEq(nft.symbol(), "NFROG");
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.totalBurned(), 0);
        assertEq(nft.price(), 2e18);
        assertEq(nft.MAX_SUPPLY(), 500);
        assertEq(nft.GENESIS_SUPPLY(), 77);
        assertEq(nft.MAX_PER_WALLET(), 10);
    }

    function testPaidMintSplitsExactlyAndEmitsBurn() public {
        vm.prank(owner);
        nft.setTreasury(treasury);
        token.fund(alice, 6e18);
        vm.startPrank(alice);
        token.approve(address(nft), 6e18);
        vm.expectEmit(true, false, false, true, address(nft));
        emit Burned(alice, 3e18, 3e18);
        nft.mint(3);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(treasury), 3e18);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), 3e18);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(nft)), 0);
        assertEq(token.allowance(alice, address(nft)), 0);
        assertEq(nft.totalBurned(), 3e18);
        assertEq(nft.totalSupply(), 3);
        assertEq(nft.mintedBy(alice), 3);
        for (uint256 id = 1; id <= 3; ++id) {
            assertEq(nft.ownerOf(id), alice);
        }
    }

    function testOwnerCannotMintForFreeAndCanPayAsTreasury() public {
        vm.prank(owner);
        vm.expectRevert();
        nft.mint(1);
        assertEq(nft.totalSupply(), 0);
        _buy(owner, 2);
        assertEq(nft.balanceOf(owner), 2);
        assertEq(token.balanceOf(owner), 2e18);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), 2e18);
    }

    function testMintQuantityAndLifetimeWalletLimit() public {
        vm.expectRevert(NightFrogs.InvalidQuantity.selector);
        nft.mint(0);
        vm.expectRevert(NightFrogs.InvalidQuantity.selector);
        nft.mint(11);
        _buy(alice, 10);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        vm.prank(alice);
        vm.expectRevert(NightFrogs.WalletLimit.selector);
        nft.mint(1);
        assertEq(nft.mintedBy(alice), 10);
    }

    function testPartialMintsReachTenExactly() public {
        _buy(alice, 4);
        _buy(alice, 6);
        assertEq(nft.balanceOf(alice), 10);
        assertEq(nft.totalSupply(), 10);
        assertEq(nft.totalBurned(), 10e18);
    }

    function testSupplyNeverExceedsFiveHundred() public {
        _sellOut();
        assertEq(nft.totalSupply(), 500);
        assertEq(nft.ownerOf(500), address(uint160(0x10000 + 49)));
        assertEq(nft.totalBurned(), 500e18);
        assertEq(token.balanceOf(owner), 500e18);
        vm.prank(bob);
        vm.expectRevert(NightFrogs.SoldOut.selector);
        nft.mint(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 501));
        nft.ownerOf(501);
    }

    function testBatchCannotCrossSupplyBoundary() public {
        for (uint256 i; i < 49; ++i) {
            _buy(address(uint160(0x20000 + i)), 10);
        }
        _buy(alice, 9);
        vm.prank(bob);
        vm.expectRevert(NightFrogs.SoldOut.selector);
        nft.mint(2);
        assertEq(nft.totalSupply(), 499);
        _buy(bob, 1);
        assertEq(nft.ownerOf(500), bob);
    }

    function testCostCeilingProtectsOpenAllowanceFromPriceRaise() public {
        token.fund(alice, 1_000e18);
        vm.prank(alice);
        token.approve(address(nft), type(uint256).max);
        vm.prank(owner);
        nft.setPrice(1_000e18); // Mined ahead of alice's pending mint that was quoted at 2 IMD.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NightFrogs.CostAboveLimit.selector, 1_000e18, 2e18));
        nft.mint(1, 2e18);
        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(nft.totalSupply(), 0);
        vm.prank(owner);
        nft.setPrice(2e18);
        vm.prank(alice);
        nft.mint(3, 6e18); // Exactly the quoted cost passes.
        assertEq(nft.balanceOf(alice), 3);
        assertEq(token.balanceOf(alice), 994e18);
        assertEq(nft.totalBurned(), 3e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NightFrogs.CostAboveLimit.selector, 2e18, 2e18 - 1));
        nft.mint(1, 2e18 - 1);
        vm.prank(alice);
        nft.mint(1, 100e18); // A ceiling above the cost never charges more than the cost.
        assertEq(token.balanceOf(alice), 992e18);
        assertEq(nft.mintedBy(alice), 4);
    }

    function testPriceAndTreasuryUpdatesPreserveSplit() public {
        vm.startPrank(owner);
        nft.setPrice(6); // Six smallest units: no rounding or minimum denomination assumption.
        nft.setTreasury(treasury);
        vm.stopPrank();
        _buy(alice, 1);
        assertEq(token.balanceOf(treasury), 3);
        assertEq(nft.totalBurned(), 3);
        vm.startPrank(owner);
        nft.setPrice(10);
        nft.setTreasury(bob);
        vm.stopPrank();
        _buy(alice, 2);
        assertEq(token.balanceOf(treasury), 3);
        assertEq(token.balanceOf(bob), 10);
        assertEq(nft.totalBurned(), 13);
    }

    function testRejectZeroOddOverflowingPricesAndBadTreasuries() public {
        vm.startPrank(owner);
        vm.expectRevert(NightFrogs.InvalidPrice.selector);
        nft.setPrice(0);
        vm.expectRevert(NightFrogs.InvalidPrice.selector);
        nft.setPrice(1);
        vm.expectRevert(NightFrogs.InvalidPrice.selector);
        nft.setPrice(2e18 + 1);
        vm.expectRevert(NightFrogs.InvalidPrice.selector);
        nft.setPrice(type(uint256).max - 1);
        vm.expectRevert(NightFrogs.InvalidAddress.selector);
        nft.setTreasury(address(0));
        vm.expectRevert(NightFrogs.InvalidAddress.selector);
        nft.setTreasury(0x000000000000000000000000000000000000dEaD);
        vm.expectRevert(NightFrogs.InvalidAddress.selector);
        nft.setTreasury(address(nft));
        vm.stopPrank();
    }

    function testAllAdminFunctionsRejectOtherCallers() public {
        bytes memory expected = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);
        vm.startPrank(alice);
        vm.expectRevert(expected);
        nft.setPrice(8);
        vm.expectRevert(expected);
        nft.setTreasury(bob);
        vm.expectRevert(expected);
        nft.configureVRF(42, TEST_KEY);
        vm.expectRevert(expected);
        nft.reveal();
        vm.expectRevert(expected);
        nft.transferOwnership(bob);
        vm.expectRevert(expected);
        nft.renounceOwnership();
        vm.stopPrank();
    }

    function testNoNativeEtherMintingOrFreeMintBackdoor() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        (bool success,) = address(nft).call{value: 1 ether}(abi.encodeWithSignature("mint(uint256)", 1));
        assertFalse(success);
        (success,) =
            address(nft).call{value: 1 ether}(abi.encodeWithSignature("mint(uint256,uint256)", 1, 2e18));
        assertFalse(success);
        (success,) = address(nft).call(abi.encodeWithSignature("ownerMint(address,uint256)", alice, 1));
        assertFalse(success);
        (success,) = address(nft).call(abi.encodeWithSignature("pause()"));
        assertFalse(success);
        (success,) = address(nft).call(abi.encodeWithSignature("upgradeTo(address)", alice));
        assertFalse(success);
        vm.stopPrank();
    }

    function testTwoStepOwnershipMovesRoyaltyRecipientOnlyOnAcceptance() public {
        (address recipient, uint256 royalty) = nft.royaltyInfo(1, 10_000);
        assertEq(recipient, owner);
        assertEq(royalty, 500);
        vm.prank(owner);
        nft.transferOwnership(bob);
        assertEq(nft.pendingOwner(), bob);
        assertEq(nft.owner(), owner);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.acceptOwnership();
        vm.prank(bob);
        nft.acceptOwnership();
        (recipient, royalty) = nft.royaltyInfo(500, type(uint256).max);
        assertEq(recipient, bob);
        assertEq(royalty, type(uint256).max / 20);
        assertEq(nft.treasury(), owner); // Separate setting, intentionally not silently redirected.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        nft.setPrice(4);
        vm.startPrank(bob);
        vm.expectRevert(NightFrogs.OwnershipRequired.selector);
        nft.renounceOwnership();
        vm.expectRevert(NightFrogs.InvalidAddress.selector);
        nft.transferOwnership(address(0));
        vm.expectRevert(NightFrogs.InvalidAddress.selector);
        nft.transferOwnership(0x000000000000000000000000000000000000dEaD);
        vm.stopPrank();
    }

    function testTransfersHaveNoFeeAndNoHoldingLimit() public {
        _buy(alice, 10);
        _buy(bob, 10);
        address collector = makeAddr("collector");
        for (uint256 i = 1; i <= 20; ++i) {
            address from = i <= 10 ? alice : bob;
            vm.prank(from);
            nft.transferFrom(from, collector, i);
        }
        assertEq(nft.balanceOf(collector), 20);
        assertEq(nft.mintedBy(collector), 0);
        assertEq(nft.totalBurned(), 20e18);
        assertEq(token.balanceOf(collector), 0);
        _buy(collector, 1);
        assertEq(nft.balanceOf(collector), 21);
        vm.prank(collector);
        nft.approve(alice, 1);
        vm.prank(alice);
        nft.transferFrom(collector, bob, 1);
        assertEq(nft.getApproved(1), address(0));
        vm.prank(collector);
        nft.setApprovalForAll(alice, true);
        vm.prank(alice);
        nft.safeTransferFrom(collector, bob, 2);
        assertEq(nft.ownerOf(2), bob);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, alice, 1));
        nft.transferFrom(bob, alice, 1);
    }

    function testStandardInterfacesAndNonexistentMetadata() public {
        assertTrue(nft.supportsInterface(0x01ffc9a7));
        assertTrue(nft.supportsInterface(0x80ac58cd));
        assertTrue(nft.supportsInterface(0x5b5e139f));
        assertTrue(nft.supportsInterface(0x2a55205a));
        assertTrue(nft.supportsInterface(0x49064906));
        assertFalse(nft.supportsInterface(0xffffffff));
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        nft.tokenURI(0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.tokenURI(1);
    }

    function testPaymentAndReceiverFailuresRollBackEverything() public {
        token.fund(alice, 2e18);
        vm.prank(alice);
        vm.expectRevert();
        nft.mint(1);
        vm.prank(alice);
        token.approve(address(nft), 2e18);
        token.setFalse(true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        nft.mint(1);
        token.setFalse(false);
        token.blockRecipient(owner); // Burn succeeds first; treasury fails second.
        vm.prank(alice);
        vm.expectRevert("recipient blocked");
        nft.mint(1);
        token.blockRecipient(address(0));
        assertEq(token.balanceOf(alice), 2e18);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), 0);
        assertEq(token.allowance(alice, address(nft)), 2e18);
        assertEq(nft.mintedBy(alice), 0);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.totalBurned(), 0);
        MintReceiver receiver = new MintReceiver(nft, token);
        receiver.configure(true, false, address(0));
        token.fund(address(receiver), 2e18);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver))
        );
        receiver.buy(1);
        assertEq(token.balanceOf(address(receiver)), 2e18);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), 0);
        assertEq(nft.totalSupply(), 0);
    }

    function testFeeOnTransferRejectedBothDirections() public {
        token.fund(alice, 4e18);
        vm.prank(alice);
        token.approve(address(nft), 4e18);
        token.setTaxes(true, false);
        vm.prank(alice);
        vm.expectRevert(NightFrogs.InexactPayment.selector);
        nft.mint(1);
        token.setTaxes(false, true);
        vm.prank(alice);
        vm.expectRevert(NightFrogs.InexactPayment.selector);
        nft.mint(1);
        token.setTaxes(false, false);
        token.setRecipientTax(owner);
        vm.prank(alice);
        vm.expectRevert(NightFrogs.InexactPayment.selector);
        nft.mint(1);
        token.setRecipientTax(address(0));
        token.setExtraPullCharge(true);
        vm.prank(alice);
        vm.expectRevert(NightFrogs.InexactPayment.selector);
        nft.mint(1);
        assertEq(token.balanceOf(alice), 4e18);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), 0);
        assertEq(nft.totalSupply(), 0);
    }

    function testMissingTokenOrWrongDecimalsCannotMint() public {
        token.setDecimals(6);
        vm.expectRevert(NightFrogs.PaymentNotConfigured.selector);
        nft.mint(1);
        vm.etch(address(token), hex"");
        vm.expectRevert(NightFrogs.PaymentNotConfigured.selector);
        nft.mint(1);
    }

    function testNoReturnTokenAndDonatedBalanceHandled() public {
        token.setNoReturn(true);
        token.fund(address(nft), 12345);
        _buy(alice, 2);
        assertEq(token.balanceOf(address(nft)), 12345);
        assertEq(nft.totalBurned(), 2e18);
    }

    function testReentrancyBlockedDuringPaymentAndReceiverCallback() public {
        token.setReentry(nft);
        MintReceiver receiver = new MintReceiver(nft, token);
        receiver.configure(false, true, bob);
        token.fund(address(receiver), 20e18);
        receiver.buy(10);
        assertFalse(token.reentrySucceeded());
        assertFalse(receiver.reentrySucceeded());
        assertEq(receiver.received(), 10);
        assertEq(nft.totalSupply(), 10);
        assertEq(nft.balanceOf(bob), 10);
        assertEq(nft.mintedBy(address(receiver)), 10);
        assertEq(nft.totalBurned(), 10e18);
    }

    function testFuzzExactAccounting(uint8 rawQuantity, uint96 rawPrice) public {
        uint256 quantity = bound(rawQuantity, 1, 10);
        uint256 evenPrice = bound(rawPrice, 1, 1e24) * 2;
        vm.prank(owner);
        nft.setPrice(evenPrice);
        vm.prank(owner);
        nft.setTreasury(treasury);
        _buy(alice, quantity);
        uint256 half = quantity * evenPrice / 2;
        assertEq(nft.totalSupply(), quantity);
        assertEq(nft.totalBurned(), half);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), half);
        assertEq(token.balanceOf(treasury), half);
        assertEq(token.balanceOf(address(nft)), 0);
        assertEq(token.balanceOf(alice), 0);
    }
}
