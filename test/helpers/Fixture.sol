// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NightFrogs} from "../../src/NightFrogs.sol";
import {FrogRenderer} from "../../src/FrogRenderer.sol";
import {ArtStore} from "../../src/art/ArtStore.sol";
import {MockIMD, MockCoordinator} from "./Mocks.sol";

abstract contract Fixture is Test {
    NightFrogs internal nft;
    FrogRenderer internal renderer;
    ArtStore internal art1;
    ArtStore internal art2;
    MockIMD internal token;
    MockCoordinator internal coordinator;
    address internal owner;
    address internal alice;
    address internal bob;
    address internal treasury;
    bytes32 internal constant TEST_KEY = keccak256("local mock gas lane");

    function setUp() public virtual {
        owner = makeAddr("explicit launch owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        treasury = makeAddr("treasury");
        art1 = ArtStore(deployCode("FrogArt1.sol:FrogArt1"));
        art2 = ArtStore(deployCode("FrogArt2.sol:FrogArt2"));
        renderer = new FrogRenderer(address(art1), address(art2));
        coordinator = new MockCoordinator();
        nft = new NightFrogs(owner, address(coordinator), address(renderer));
        MockIMD implementation = new MockIMD();
        vm.etch(nft.IMD(), address(implementation).code);
        token = MockIMD(nft.IMD());
        token.setDecimals(18);
    }

    function _buy(address buyer, uint256 quantity) internal {
        uint256 cost = quantity * nft.price();
        token.fund(buyer, cost);
        vm.startPrank(buyer);
        token.approve(address(nft), cost);
        nft.mint(quantity);
        vm.stopPrank();
    }

    function _sellOut() internal {
        for (uint256 i; i < 50; ++i) {
            _buy(address(uint160(0x10000 + i)), 10);
        }
    }

    function _request() internal returns (uint256 id) {
        vm.startPrank(owner);
        nft.configureVRF(42, TEST_KEY);
        id = nft.reveal();
        vm.stopPrank();
    }

    function _fulfill(uint256 word) internal {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        coordinator.fulfill(nft, nft.revealRequestId(), words);
    }
}
