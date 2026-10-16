// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {FrogRenderer} from "../src/FrogRenderer.sol";

/// @notice The declared rarity weights must actually be realised by the onchain draw, and the
/// Genesis / captain reservations must hold for every seed. These are statistical properties of
/// the implemented selector, not a re-implementation of it.
contract RarityTest is Fixture {
    uint256 internal constant WORDS = 16;
    uint256 internal constant FIRST_CREW = 78;
    uint256 internal constant DRAWS = WORDS * (500 - FIRST_CREW + 1); // 6768 non-Genesis draws per layer

    function _tally() internal view returns (uint256[8][7] memory counts) {
        for (uint256 w = 1; w <= WORDS; ++w) {
            uint256 word = uint256(keccak256(abi.encode("rarity sample", w)));
            for (uint256 id = FIRST_CREW; id <= 500; ++id) {
                uint8[7] memory selected = renderer.traits(id, word);
                for (uint8 layer; layer < 7; ++layer) {
                    ++counts[layer][selected[layer]];
                }
            }
        }
    }

    /// @dev Every realised frequency sits within a wide band around its weight (about +/- 40 percent
    /// relative, plus an absolute floor for the one-percent legendaries).
    function testRealisedFrequenciesTrackDeclaredWeights() public view {
        uint256[8][7] memory counts = _tally();
        uint8[7] memory sizes = [6, 6, 8, 6, 8, 8, 6];
        for (uint8 layer; layer < 7; ++layer) {
            uint256 total;
            for (uint8 index; index < sizes[layer]; ++index) {
                if (layer == 0 && index == 5) {
                    assertEq(counts[0][5], 0, "Genesis background drawn for a crew token");
                    continue;
                }
                uint256 expected = DRAWS * renderer.traitWeight(layer, index) / 100;
                uint256 slack = expected * 2 / 5 + 25;
                assertGe(counts[layer][index] + slack, expected, "trait far rarer than its weight");
                assertLe(counts[layer][index], expected + slack, "trait far commoner than its weight");
                assertGt(counts[layer][index], 0, "a weighted trait never appears");
                total += counts[layer][index];
            }
            assertEq(total, DRAWS, "draws lost or duplicated in a layer");
        }
    }

    function testLegendariesAreRarerThanCommons() public view {
        uint256[8][7] memory counts = _tally();
        // Chrome skin (1) and Moonlight Halo (1) under Monocle (2) under Gold (4) under Classic Green (35).
        assertLt(counts[2][7], counts[4][7]);
        assertLt(counts[5][6], counts[4][7]);
        assertLt(counts[4][7], counts[2][6]);
        assertLt(counts[2][6], counts[2][0]);
        // Gold Tracksuit (3) under every other body.
        for (uint8 index; index < 5; ++index) {
            assertLt(counts[1][5], counts[1][index]);
        }
        // Headwear "None" (14) and Accessory "None" (14) are not the majority outcome.
        assertLt(counts[5][7] * 2, DRAWS);
        assertLt(counts[6][5] * 2, DRAWS);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzGenesisBackgroundExactlyForFirstSeventySeven(uint256 word, uint16 rawId) public view {
        uint256 id = bound(rawId, 1, 500);
        uint8[7] memory selected = renderer.traits(id, word);
        if (id <= 77) {
            assertEq(selected[0], 5);
            assertEq(renderer.traitName(0, selected[0]), "Genesis Sunburst");
        } else {
            assertLt(selected[0], 5);
        }
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzTraitsDependOnBothSeedAndTokenId(uint256 wordA, uint256 wordB, uint16 rawA, uint16 rawB)
        public
        view
    {
        uint256 idA = bound(rawA, 2, 500);
        uint256 idB = bound(rawB, 2, 500);
        // Same inputs: same output (pure determinism).
        assertEq(abi.encode(renderer.traits(idA, wordA)), abi.encode(renderer.traits(idA, wordA)));
        // The reserved captain ignores the seed; nobody else is pinned to the captain's set.
        assertEq(abi.encode(renderer.traits(1, wordA)), abi.encode(renderer.traits(1, wordB)));
        if (idA != 1) {
            uint8[7] memory s = renderer.traits(idA, wordA);
            bool captainSet = s[1] == 5 && s[2] == 7 && s[3] == 0 && s[4] == 1 && s[5] == 3 && s[6] == 0;
            assertFalse(captainSet && idA > 77, "crew token reproduced the captain's full set");
        }
        // Every layer of a crew token stays inside its own trait count for any seed.
        uint8[7] memory sizes = [6, 6, 8, 6, 8, 8, 6];
        uint8[7] memory b = renderer.traits(idB, wordB);
        for (uint8 layer; layer < 7; ++layer) {
            assertLt(b[layer], sizes[layer]);
        }
    }

    function testCaptainSetIsTheRareSetItClaims() public view {
        uint8[7] memory captain = renderer.traits(1, 0);
        assertEq(renderer.traitName(0, captain[0]), "Genesis Sunburst");
        assertEq(renderer.traitName(1, captain[1]), "Gold Tracksuit");
        assertEq(renderer.traitName(2, captain[2]), "Chrome");
        assertEq(renderer.traitName(4, captain[4]), "Laser Eyes");
        assertEq(renderer.traitName(5, captain[5]), "Gold Crown");
        assertEq(renderer.traitName(6, captain[6]), "SHIFT Chain");
        assertEq(renderer.traitWeight(2, captain[2]), 1);
        assertEq(renderer.traitWeight(1, captain[1]), 3);
    }

    function testTraitNamesMatchTheBrief() public view {
        assertEq(renderer.traitName(0, 0), "Neon City");
        assertEq(renderer.traitName(0, 4), "Server Corridor");
        assertEq(renderer.traitName(1, 2), "Hi-vis Safety Vest");
        assertEq(renderer.traitName(1, 4), "NIGHTSHIFT Jumpsuit");
        assertEq(renderer.traitName(2, 3), "Mint Zombie");
        assertEq(renderer.traitName(3, 1), "Toothpick");
        assertEq(renderer.traitName(4, 3), "Cyan VR Visor");
        assertEq(renderer.traitName(4, 7), "Monocle");
        assertEq(renderer.traitName(5, 0), "Headlamp Hard Hat");
        assertEq(renderer.traitName(5, 6), "Moonlight Halo");
        assertEq(renderer.traitName(5, 7), "None");
        assertEq(renderer.traitName(6, 1), "Crew ID Badge");
        assertEq(renderer.traitName(6, 4), "IMD Swarm Earpiece");
        assertEq(renderer.traitName(6, 5), "None");
        // "None" variants contribute no markup, every drawn layer does.
        assertEq(bytes(renderer.traitSVG(5, 7)).length, 0);
        assertEq(bytes(renderer.traitSVG(6, 5)).length, 0);
        assertGt(bytes(renderer.traitSVG(0, 5)).length, 0);
    }

    function testRendererRejectsOutOfRangeEverywhere() public {
        vm.expectRevert(FrogRenderer.InvalidTokenId.selector);
        renderer.traits(0, 1);
        vm.expectRevert(FrogRenderer.InvalidTokenId.selector);
        renderer.traits(501, 1);
        vm.expectRevert(FrogRenderer.InvalidTokenId.selector);
        renderer.imageSVG(type(uint256).max, true, 1);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitWeight(7, 0);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitWeight(0, 6);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitName(2, 8);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitSVG(6, 6);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitName(type(uint8).max, type(uint8).max);
    }
}
