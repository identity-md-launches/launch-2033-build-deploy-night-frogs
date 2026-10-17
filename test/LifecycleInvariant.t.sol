// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Fixture} from "./helpers/Fixture.sol";
import {NightFrogs} from "../src/NightFrogs.sol";
import {FrogRenderer} from "../src/FrogRenderer.sol";
import {MockIMD, MockCoordinator} from "./helpers/Mocks.sol";

/// @dev Drives the whole collection life: paid mints, VRF configuration, the sale-closing reveal request,
/// time passing so a request goes stale and gets replaced, genuine, abandoned and foreign fulfillment
/// attempts, transfers and two-step ownership handover, in random order. Ghost variables record what the
/// contract must now hold; the invariants compare them after every call.
contract LifecycleHandler is Test {
    NightFrogs public immutable nft;
    MockIMD public immutable token;
    MockCoordinator public immutable coordinator;
    FrogRenderer public immutable renderer;

    uint256 public constant ACTORS = 64;
    uint256 public constant FILLERS = 50;
    uint256 public constant RETRY_DELAY = 3 days;

    // Ghost state.
    address public immutable initialOwner;
    address public ghostOwner;
    address public ghostPending;
    bool public ghostRequested;
    uint256 public ghostRequestId;
    uint256 public ghostRequestedAt;
    uint256 public ghostClosedSupply;
    uint256 public ghostRequests; // coordinator requests the contract has made
    uint256 public ghostSub;
    bytes32 public ghostKey;
    bool public ghostRevealed;
    uint256 public ghostWord;
    uint256 public paid;
    uint256 public fillers;
    uint256 public foreignAttempts;
    uint256 public genuineAttempts;
    uint256 public revealAttempts;
    uint256 public replacements;
    uint256 public abandonedAttempts;

    constructor(
        NightFrogs nft_,
        MockIMD token_,
        MockCoordinator coordinator_,
        FrogRenderer renderer_,
        address owner_
    ) {
        nft = nft_;
        token = token_;
        coordinator = coordinator_;
        renderer = renderer_;
        initialOwner = owner_;
        ghostOwner = owner_;
    }

    function actor(uint256 index) public pure returns (address) {
        return address(uint160(0x40000 + index % ACTORS));
    }

    function filler(uint256 index) public pure returns (address) {
        return address(uint160(0x50000 + index));
    }

    /// @dev Everyone who could hold a frog in this harness.
    function holders() public view returns (address[] memory list) {
        list = new address[](ACTORS + fillers + 1);
        for (uint256 i; i < ACTORS; ++i) {
            list[i] = actor(i);
        }
        for (uint256 i; i < fillers; ++i) {
            list[ACTORS + i] = filler(i);
        }
        list[ACTORS + fillers] = initialOwner; // later owners are actors and already listed
    }

    function buy(uint256 actorIndex, uint256 rawQuantity) external {
        address buyer = actor(actorIndex);
        uint256 quantity = bound(rawQuantity, 0, 11);
        uint256 cost = nft.price() * quantity;
        token.fund(buyer, cost);
        uint256 supplyBefore = nft.totalSupply();
        uint256 mintedBefore = nft.mintedBy(buyer);
        vm.startPrank(buyer);
        token.approve(address(nft), cost);
        // Half the buyers use the cost-ceiling overload with exactly the quoted total.
        bytes memory data = rawQuantity % 2 == 1
            ? abi.encodeWithSignature("mint(uint256,uint256)", quantity, cost)
            : abi.encodeWithSignature("mint(uint256)", quantity);
        (bool ok,) = address(nft).call(data);
        if (ok) {
            assertTrue(quantity >= 1 && quantity <= 10, "quantity outside 1..10 accepted");
            assertFalse(ghostRequested, "mint accepted after the reveal request closed the sale");
            assertLe(supplyBefore + quantity, 500, "supply cap crossed");
            assertLe(mintedBefore + quantity, 10, "wallet cap crossed");
            paid += cost;
            for (uint256 i = 1; i <= quantity; ++i) {
                assertEq(nft.ownerOf(supplyBefore + i), buyer, "sequential id not owned by payer");
            }
        } else {
            bool legitimate = quantity == 0 || quantity > 10 || ghostRequested
                || supplyBefore + quantity > 500 || mintedBefore + quantity > 10;
            assertTrue(legitimate, "a valid paid mint reverted");
            assertEq(nft.totalSupply(), supplyBefore, "failed mint changed supply");
            assertEq(nft.mintedBy(buyer), mintedBefore, "failed mint changed the wallet count");
        }
        vm.stopPrank();
    }

    /// @dev Sells the remaining supply to fresh wallets so sequences can reach the sellout path.
    function fillRemaining(uint256 rawBatches) external {
        if (ghostRequested) return;
        uint256 batches = bound(rawBatches, 1, FILLERS);
        for (uint256 i; i < batches && nft.totalSupply() + 10 <= 500 && fillers < FILLERS; ++i) {
            address buyer = filler(fillers++);
            uint256 cost = nft.price() * 10;
            token.fund(buyer, cost);
            vm.startPrank(buyer);
            token.approve(address(nft), cost);
            nft.mint(10);
            vm.stopPrank();
            paid += cost;
        }
    }

    /// @dev What the model says about staleness: an unfulfilled request older than the retry delay.
    function ghostStale() public view returns (bool) {
        return ghostRequested && !ghostRevealed && block.timestamp >= ghostRequestedAt + RETRY_DELAY;
    }

    /// @dev Time passes in steps from a minute to a little over the retry delay, so sequences reach
    /// both sides of the stale boundary (including the exact second).
    function warp(uint256 rawDelta) external {
        uint256 delta;
        if (rawDelta % 7 == 0 && ghostRequested && !ghostRevealed) {
            uint256 edge = ghostRequestedAt + RETRY_DELAY;
            delta = edge > block.timestamp ? edge - block.timestamp : 0; // land exactly on the boundary
        } else {
            delta = bound(rawDelta, 1 minutes, RETRY_DELAY + 1 hours);
        }
        vm.warp(block.timestamp + delta);
    }

    function configure(uint256 rawSub, uint256 rawKey) external {
        uint256 sub = bound(rawSub, 0, 3);
        bytes32 key = rawKey % 3 == 0 ? bytes32(0) : keccak256(abi.encode(rawKey));
        bool locked = ghostRequested && !ghostStale();
        vm.prank(ghostOwner);
        try nft.configureVRF(sub, key) {
            assertFalse(locked, "configuration changed while a live request is pending");
            assertFalse(ghostRevealed, "configuration changed after reveal");
            assertTrue(sub != 0 && key != bytes32(0), "zero configuration accepted");
            ghostSub = sub;
            ghostKey = key;
        } catch {
            assertTrue(locked || sub == 0 || key == bytes32(0), "valid configuration rejected");
        }
    }

    function reveal() external {
        ++revealAttempts;
        uint256 requestsBefore = coordinator.requests();
        uint256 supplyBefore = nft.totalSupply();
        bool replacing = ghostRequested; // only legitimate when stale
        bool locked = ghostRequested && !ghostStale();
        vm.prank(ghostOwner);
        try nft.reveal() returns (uint256 id) {
            assertFalse(locked, "second request accepted while the first is live");
            assertFalse(ghostRevealed, "request accepted after reveal");
            assertGt(supplyBefore, 0, "reveal with nothing minted");
            assertTrue(ghostSub != 0 && ghostKey != bytes32(0), "reveal without configuration");
            assertEq(coordinator.requests(), requestsBefore + 1, "request not forwarded");
            assertEq(coordinator.lastSub(), ghostSub);
            assertEq(coordinator.lastKey(), ghostKey);
            assertEq(nft.totalSupply(), supplyBefore, "request changed supply");
            if (replacing) {
                assertEq(supplyBefore, ghostClosedSupply, "supply moved between request and replacement");
                assertTrue(id != ghostRequestId, "replacement reused the abandoned id");
                ++replacements;
            } else {
                ghostRequested = true;
                ghostClosedSupply = supplyBefore;
            }
            ghostRequestId = id;
            ghostRequestedAt = block.timestamp;
            ++ghostRequests;
        } catch {
            assertEq(coordinator.requests(), requestsBefore, "failed reveal still requested");
            assertTrue(
                locked || ghostRevealed || supplyBefore == 0 || ghostSub == 0 || ghostKey == bytes32(0),
                "valid reveal rejected"
            );
        }
    }

    /// @dev The coordinator delivers: only the latest recorded request id with exactly one word may
    /// land, once. Ids below the current one are abandoned requests; above it, never issued.
    function fulfill(uint256 rawId, uint256 word, uint256 rawLength) external {
        ++genuineAttempts;
        uint256 id;
        uint256 pick = rawId % 4;
        if (pick == 0) id = 0;
        else if (pick == 1) id = ghostRequestId; // the live one (0 before any request)
        else if (pick == 2) id = ghostRequestId > 0 ? ghostRequestId - 1 : 0; // abandoned or never issued
        else id = ghostRequestId + 1; // not issued yet
        if (ghostRequested && id != 0 && id < ghostRequestId) ++abandonedAttempts;
        uint256 length = rawLength % 3;
        uint256[] memory words = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            words[i] = word;
        }
        try coordinator.fulfill(nft, id, words) {
            assertTrue(ghostRequested, "fulfilled without request");
            assertFalse(ghostRevealed, "fulfilled twice");
            assertEq(id, ghostRequestId, "foreign or abandoned request id accepted");
            assertEq(length, 1, "wrong word count accepted");
            ghostRevealed = true;
            ghostWord = word;
            // Metadata flips with the seed, and the captain keeps the reserved set.
            assertEq(nft.tokenURI(1), renderer.tokenURI(1, true, word));
            assertNotEq(nft.tokenURI(1), renderer.tokenURI(1, false, 0));
        } catch {
            assertTrue(
                !ghostRequested || ghostRevealed || id != ghostRequestId || length != 1,
                "valid fulfillment rejected"
            );
        }
    }

    /// @dev Anyone but the coordinator, including the owner, is refused even with the right payload.
    function foreignFulfill(uint256 actorIndex, uint256 word, bool asOwner) external {
        ++foreignAttempts;
        address caller = asOwner ? ghostOwner : actor(actorIndex);
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        vm.prank(caller);
        try nft.rawFulfillRandomWords(ghostRequestId, words) {
            assertTrue(false, "non-coordinator fulfilled the reveal");
        } catch (bytes memory reason) {
            assertEq(bytes32(bytes4(reason)), bytes32(NightFrogs.OnlyCoordinator.selector));
        }
    }

    function move(uint256 rawId, uint256 recipientIndex) external {
        uint256 supply = nft.totalSupply();
        if (supply == 0) return;
        uint256 id = rawId % supply + 1;
        address from = nft.ownerOf(id);
        bool checkMetadata = rawId % 16 == 0; // metadata is costly to render; sample it
        string memory before = checkMetadata ? nft.tokenURI(id) : "";
        vm.prank(from);
        nft.transferFrom(from, actor(recipientIndex), id);
        assertEq(nft.ownerOf(id), actor(recipientIndex));
        if (checkMetadata) assertEq(nft.tokenURI(id), before, "transfer changed metadata");
    }

    function changePrice(uint256 rawPrice) external {
        uint256 next = bound(rawPrice, 1, 100e18) * 2;
        vm.prank(ghostOwner);
        nft.setPrice(next);
        assertEq(nft.price(), next);
    }

    function changeTreasury(uint256 actorIndex) external {
        vm.prank(ghostOwner);
        nft.setTreasury(actor(actorIndex));
    }

    function nominate(uint256 actorIndex) external {
        address next = actor(actorIndex);
        vm.prank(ghostOwner);
        nft.transferOwnership(next);
        ghostPending = next;
        assertEq(nft.owner(), ghostOwner, "nomination moved ownership early");
    }

    function accept() external {
        if (ghostPending == address(0)) return;
        vm.prank(ghostPending);
        nft.acceptOwnership();
        ghostOwner = ghostPending;
        ghostPending = address(0);
    }

    function strangerAccepts(uint256 actorIndex) external {
        address stranger = actor(actorIndex);
        if (stranger == ghostPending) return;
        vm.prank(stranger);
        try nft.acceptOwnership() {
            assertTrue(false, "stranger took ownership");
        } catch {}
    }
}

/// forge-config: default.invariant.runs = 96
/// forge-config: default.invariant.depth = 60
/// forge-config: default.invariant.fail-on-revert = false
contract LifecycleInvariant is Fixture {
    LifecycleHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new LifecycleHandler(nft, token, coordinator, renderer, owner);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = handler.buy.selector;
        selectors[1] = handler.buy.selector;
        selectors[2] = handler.fillRemaining.selector;
        selectors[3] = handler.configure.selector;
        selectors[4] = handler.reveal.selector;
        selectors[5] = handler.reveal.selector;
        selectors[6] = handler.fulfill.selector;
        selectors[7] = handler.foreignFulfill.selector;
        selectors[8] = handler.move.selector;
        selectors[9] = handler.changePrice.selector;
        selectors[10] = handler.changeTreasury.selector;
        selectors[11] = handler.nominate.selector;
        selectors[12] = handler.accept.selector;
        selectors[13] = handler.strangerAccepts.selector;
        selectors[14] = handler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev Reveal is a one-way state machine: unconfigured -> configured -> requested -> revealed.
    /// A request may be replaced only while it is stale, and never once a word has landed.
    function invariant_revealStateMachineNeverReopens() public view {
        assertEq(nft.revealRequested(), handler.ghostRequested(), "request flag drifted");
        assertEq(nft.revealed(), handler.ghostRevealed(), "revealed flag drifted");
        assertEq(nft.revealRequestStale(), handler.ghostStale(), "staleness drifted from the model");
        if (nft.revealed()) {
            assertTrue(nft.revealRequested(), "revealed without request");
            assertEq(nft.randomWord(), handler.ghostWord(), "seed changed after reveal");
            assertFalse(nft.revealRequestStale(), "a fulfilled request reported stale");
        } else {
            assertEq(nft.randomWord(), 0, "seed set before reveal");
        }
        if (nft.revealRequested()) {
            assertEq(nft.revealRequestId(), handler.ghostRequestId(), "request id drifted");
            assertEq(nft.revealRequestedAt(), handler.ghostRequestedAt(), "request time drifted");
            assertEq(nft.subscriptionId(), handler.ghostSub(), "subscription drifted");
            assertEq(nft.keyHash(), handler.ghostKey(), "key hash drifted");
            assertEq(coordinator.requests(), handler.ghostRequests(), "coordinator request count drifted");
            assertEq(handler.ghostRequests(), 1 + handler.replacements(), "requests != 1 + replacements");
            assertGe(nft.revealRequestId(), 1);
        } else {
            assertEq(coordinator.requests(), 0, "coordinator asked without request flag");
            assertEq(nft.revealRequestId(), 0);
            assertEq(nft.revealRequestedAt(), 0);
            assertFalse(nft.revealRequestStale());
        }
    }

    /// @dev The first request fixes the supply for good: no mint lands afterwards at any supply.
    function invariant_requestFreezesSupply() public view {
        if (nft.revealRequested()) {
            assertGt(handler.ghostClosedSupply(), 0, "sale closed with nothing minted");
            assertEq(nft.totalSupply(), handler.ghostClosedSupply(), "supply changed after the request");
        }
    }

    /// @dev The two-step owner is the royalty recipient and is never a dead or self address.
    function invariant_ownerIsAccountableAndReceivesRoyalties() public view {
        address current = nft.owner();
        assertEq(current, handler.ghostOwner(), "owner drifted from accepted handover");
        assertEq(nft.pendingOwner(), handler.ghostPending(), "pending owner drifted");
        assertTrue(current != address(0) && current != nft.BURN_ADDRESS() && current != address(nft));
        (address recipient, uint256 amount) = nft.royaltyInfo(1, 1_000_000);
        assertEq(recipient, current);
        assertEq(amount, 50_000);
    }

    /// @dev Exactly half of all payments is burned, the contract keeps nothing, and every frog is held.
    function invariant_valueConservationAndSupply() public view {
        uint256 half = handler.paid() / 2;
        assertEq(nft.totalBurned(), half, "totalBurned drifted from payments");
        assertEq(token.balanceOf(nft.BURN_ADDRESS()), half, "burn address drifted");
        assertEq(token.balanceOf(address(nft)), 0, "collection retained IMD");
        assertLe(nft.totalSupply(), 500);
        address[] memory list = handler.holders();
        uint256 held;
        uint256 lifetime;
        for (uint256 i; i < list.length; ++i) {
            held += nft.balanceOf(list[i]);
            uint256 minted = nft.mintedBy(list[i]);
            assertLe(minted, 10, "wallet minted more than ten");
            lifetime += minted;
        }
        assertEq(held, nft.totalSupply(), "frogs held != supply");
        assertEq(lifetime, nft.totalSupply(), "lifetime mints != supply");
    }
}
