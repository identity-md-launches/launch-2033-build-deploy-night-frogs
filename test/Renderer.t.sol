// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {Decode} from "./helpers/Decode.sol";
import {FrogRenderer} from "../src/FrogRenderer.sol";
import {ArtStore} from "../src/art/ArtStore.sol";

contract RendererTest is Fixture {
    using Decode for string;

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

    function testMoonPlaceholderUntilFulfilledAndJSONHasEmbeddedSVG() public {
        _buy(alice, 1);
        string memory json = nft.tokenURI(1).dataURI("data:application/json;base64,");
        assertEq(vm.parseJsonString(json, ".name"), "NIGHT FROGS #1");
        assertEq(vm.parseJsonString(json, ".attributes[0].trait_type"), "Status");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), "Awaiting first watch");
        string memory svg = vm.parseJsonString(json, ".image").dataURI("data:image/svg+xml;base64,");
        assertTrue(_contains(svg, "THE CREW IS CLOCKING IN"));
        assertTrue(_contains(svg, 'viewBox="0 0 1000 1000"'));
        assertFalse(_contains(svg, '<use href="#frog-head"/>'));
        assertEq(svg, renderer.imageSVG(1, false, 0));
    }

    function testRevealChangesMetadataAndCaptainHasExclusiveSignature() public {
        _sellOut();
        string memory beforeURI = nft.tokenURI(1);
        _request();
        assertEq(beforeURI, nft.tokenURI(1));
        _fulfill(20261016);
        string memory afterURI = nft.tokenURI(1);
        assertNotEq(beforeURI, afterURI);
        string memory json = afterURI.dataURI("data:application/json;base64,");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), "Genesis Sunburst");
        assertEq(vm.parseJsonString(json, ".attributes[2].value"), "Chrome");
        assertEq(vm.parseJsonString(json, ".attributes[7].value"), "Genesis");
        assertEq(vm.parseJsonString(json, ".attributes[8].value"), "Zero-Sleep Captain / 1 of 1");
        string memory svg = vm.parseJsonString(json, ".image").dataURI("data:image/svg+xml;base64,");
        assertTrue(_contains(svg, "NO SLEEP"));
        assertTrue(_contains(svg, "GENESIS"));
        string memory normal = nft.tokenURI(78).dataURI("data:application/json;base64,");
        assertEq(vm.parseJsonString(normal, ".attributes[7].value"), "Night Crew");
        assertEq(vm.parseJsonString(normal, ".attributes[8].value"), "Crew Issue");
        assertEq(nft.tokenURI(1), afterURI);
    }

    function testAllAttributesMatchSelectedLayerNames() public {
        uint256 id = 178;
        uint256 word = 90210;
        uint8[7] memory selected = renderer.traits(id, word);
        string memory json = renderer.tokenURI(id, true, word).dataURI("data:application/json;base64,");
        string[7] memory categories = ["Background", "Body", "Skin", "Mouth", "Eyes", "Headwear", "Accessory"];
        for (uint8 layer; layer < 7; ++layer) {
            string memory prefix = string.concat(".attributes[", vm.toString(layer), "]");
            assertEq(vm.parseJsonString(json, string.concat(prefix, ".trait_type")), categories[layer]);
            assertEq(
                vm.parseJsonString(json, string.concat(prefix, ".value")),
                renderer.traitName(layer, selected[layer])
            );
        }
        string memory image = vm.parseJsonString(json, ".image").dataURI("data:image/svg+xml;base64,");
        assertEq(image, renderer.imageSVG(id, true, word));
        assertTrue(_contains(image, "feTurbulence"));
        assertTrue(_contains(image, "vignette"));
        assertTrue(_contains(image, "#B05A44"));
    }

    function testAllFiveHundredHaveInRangeDeterministicTraitsAndGenesisBoundary() public view {
        uint8[7] memory counts = [6, 6, 8, 6, 8, 8, 6];
        for (uint256 id = 1; id <= 500; ++id) {
            uint8[7] memory selected = renderer.traits(id, 20261016);
            assertEq(abi.encode(selected), abi.encode(renderer.traits(id, 20261016)));
            for (uint8 layer; layer < 7; ++layer) {
                assertLt(selected[layer], counts[layer]);
            }
            if (id <= 77) assertEq(selected[0], 5);
            else assertLt(selected[0], 5);
        }
        assertNotEq(abi.encode(renderer.traits(78, 1)), abi.encode(renderer.traits(78, 2)));
        assertNotEq(abi.encode(renderer.traits(78, 1)), abi.encode(renderer.traits(79, 1)));
    }

    function testEveryTraitIsStoredAndWeightsSumCorrectly() public view {
        uint8[7] memory counts = [6, 6, 8, 6, 8, 8, 6];
        for (uint8 layer; layer < 7; ++layer) {
            uint256 sum;
            for (uint8 i; i < counts[layer]; ++i) {
                assertGt(bytes(renderer.traitName(layer, i)).length, 0);
                uint256 weight = renderer.traitWeight(layer, i);
                assertGt(weight, 0);
                if (layer != 0 || i != 5) sum += weight;
                if (!((layer == 5 && i == 7) || (layer == 6 && i == 5))) {
                    assertGt(bytes(renderer.traitSVG(layer, i)).length, 0);
                }
            }
            assertEq(sum, 100);
        }
        assertEq(renderer.traitWeight(2, 7), 1);
        assertEq(renderer.traitWeight(5, 6), 1);
        assertEq(renderer.traitWeight(4, 7), 2);
    }

    function testBadgeIncludesActualTokenNumber() public {
        uint256 badgeId;
        for (uint256 id = 2; id <= 500; ++id) {
            uint8[7] memory selected = renderer.traits(id, 20261016);
            if (selected[6] == 1) {
                badgeId = id;
                break;
            }
        }
        assertGt(badgeId, 0);
        string memory svg = renderer.imageSVG(badgeId, true, 20261016);
        assertTrue(_contains(svg, string.concat('text-anchor="middle">#', vm.toString(badgeId), "</text>")));
        assertTrue(_contains(svg, "NIGHT CREW"));
    }

    function testInvalidTokenAndTraitIndicesFailClearly() public {
        vm.expectRevert(FrogRenderer.InvalidTokenId.selector);
        renderer.imageSVG(0, true, 1);
        vm.expectRevert(FrogRenderer.InvalidTokenId.selector);
        renderer.tokenURI(501, true, 1);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitName(7, 0);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitSVG(0, 6);
        vm.expectRevert(FrogRenderer.InvalidTrait.selector);
        renderer.traitWeight(5, 8);
        vm.expectRevert(ArtStore.InvalidRecord.selector);
        art1.read(19);
        vm.expectRevert(ArtStore.InvalidRecord.selector);
        art2.read(type(uint256).max);
    }

    function testFuzzTraitBoundsAndCaptainReservation(uint256 word, uint16 rawId) public view {
        uint256 id = uint256(rawId) % 500 + 1;
        uint8[7] memory selected = renderer.traits(id, word);
        uint8[7] memory counts = [6, 6, 8, 6, 8, 8, 6];
        for (uint8 i; i < 7; ++i) {
            assertLt(selected[i], counts[i]);
        }
        if (id <= 77) assertEq(selected[0], 5);
        else assertLt(selected[0], 5);
        assertEq(abi.encode(renderer.traits(1, word)), abi.encode([uint8(5), 5, 7, 0, 1, 3, 0]));
    }
}
