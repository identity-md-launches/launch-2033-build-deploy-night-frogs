// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Fixture} from "./helpers/Fixture.sol";
import {NightFrogs} from "../src/NightFrogs.sol";
import {MockIMD} from "./helpers/Mocks.sol";

contract AccountingHandler is Test {
    NightFrogs public immutable nft;
    MockIMD public immutable token;
    address public immutable owner;
    uint256 public paid;
    uint256 public successfulMints;
    uint256 public receivedNFTs;
    uint256 public transferred;
    uint256 public supplyAtClose;
    mapping(address => uint256) public expectedTreasury;
    address[4] public treasuries;

    constructor(NightFrogs nft_, MockIMD token_, address owner_) {
        nft = nft_;
        token = token_;
        owner = owner_;
        treasuries = [owner_, address(0x70001), address(0x70002), address(0x70003)];
    }

    function actor(uint256 index) public pure returns (address) {
        return address(uint160(0x30000 + index % 64));
    }

    function buy(uint256 actorIndex, uint256 rawQuantity) external {
        address buyer = actor(actorIndex);
        uint256 quantity = bound(rawQuantity, 1, 12);
        uint256 cost = nft.price() * quantity;
        token.fund(buyer, cost);
        address currentTreasury = nft.treasury();
        vm.startPrank(buyer);
        token.approve(address(nft), cost);
        try nft.mint(quantity) {
            paid += cost;
            ++successfulMints;
            receivedNFTs += quantity;
            expectedTreasury[currentTreasury] += cost / 2;
        } catch {}
        vm.stopPrank();
    }

    function changePrice(uint256 rawPrice) external {
        uint256 nextPrice = bound(rawPrice, 1, 100e18) * 2;
        vm.prank(owner);
        nft.setPrice(nextPrice);
    }

    function changeTreasury(uint256 choice) external {
        vm.prank(owner);
        nft.setTreasury(treasuries[choice % 4]);
    }

    /// @dev The owner may end the sale at any point; later buys must fail and supply must freeze.
    function closeSale() external {
        if (nft.totalSupply() == 0 || nft.revealRequested()) return;
        vm.startPrank(owner);
        nft.configureVRF(42, keccak256("local mock gas lane"));
        nft.reveal();
        vm.stopPrank();
        supplyAtClose = nft.totalSupply();
    }

    function move(uint256 rawId, uint256 recipientIndex) external {
        uint256 supply = nft.totalSupply();
        if (supply == 0) return;
        uint256 id = rawId % supply + 1;
        address from = nft.ownerOf(id);
        vm.prank(from);
        nft.transferFrom(from, actor(recipientIndex), id);
        ++transferred;
    }
}

contract AccountingInvariant is Fixture {
    AccountingHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new AccountingHandler(nft, token, owner);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.buy.selector;
        selectors[1] = handler.changePrice.selector;
        selectors[2] = handler.changeTreasury.selector;
        selectors[3] = handler.move.selector;
        selectors[4] = handler.closeSale.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantExactBurnAndTreasuryConservation() public view {
        uint256 half = handler.paid() / 2;
        assertEq(nft.totalBurned(), half);
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), half);
        uint256 credited;
        for (uint256 i; i < 4; ++i) {
            address recipient = handler.treasuries(i);
            uint256 expected = handler.expectedTreasury(recipient);
            assertEq(token.balanceOf(recipient), expected);
            credited += expected;
        }
        assertEq(credited, half);
        assertEq(token.balanceOf(address(nft)), 0);
    }

    function invariantSupplyAndLifetimeWalletCaps() public view {
        assertLe(nft.totalSupply(), 500);
        assertEq(nft.totalSupply(), handler.receivedNFTs());
        uint256 lifetime;
        uint256 held;
        for (uint256 i; i < 64; ++i) {
            address user = handler.actor(i);
            uint256 minted = nft.mintedBy(user);
            assertLe(minted, 10);
            lifetime += minted;
            held += nft.balanceOf(user);
        }
        assertEq(lifetime, nft.totalSupply());
        assertEq(held, nft.totalSupply());
    }

    function invariantSupplyFrozenOnceRevealRequested() public view {
        if (nft.revealRequested()) {
            assertEq(nft.totalSupply(), handler.supplyAtClose());
            assertGt(nft.totalSupply(), 0);
        } else {
            assertEq(handler.supplyAtClose(), 0);
        }
    }
}
