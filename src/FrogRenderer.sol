// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ArtStore} from "./art/ArtStore.sol";

/// @notice Immutable, self-contained SVG + JSON renderer. No offchain art or mutable base URI.
contract FrogRenderer {
    using Strings for uint256;

    ArtStore public immutable art1;
    ArtStore public immutable art2;

    error InvalidTokenId();
    error InvalidTrait();
    error InvalidArtStore();

    constructor(address art1_, address art2_) {
        if (art1_ == address(0) || art2_ == address(0)) revert InvalidArtStore();
        art1 = ArtStore(art1_);
        art2 = ArtStore(art2_);
    }

    /// @notice Independent, domain-separated weighted draws from the one verified collection word.
    /// #1 is the reserved Zero-Sleep Captain; every Genesis background is golden.
    function traits(uint256 tokenId, uint256 word) public pure returns (uint8[7] memory selected) {
        _validate(tokenId);
        if (tokenId == 1) return [uint8(5), 5, 7, 0, 1, 3, 0];
        for (uint8 layer; layer < 7; ++layer) {
            if (layer == 0 && tokenId <= 77) {
                selected[0] = 5;
            } else {
                uint256 roll = uint256(keccak256(abi.encode("NIGHT_FROGS_V1", word, tokenId, layer))) % 100;
                bytes memory weights = _weights(layer);
                for (uint8 index; index < weights.length; ++index) {
                    uint256 weight = uint8(weights[index]);
                    if (roll < weight) {
                        selected[layer] = index;
                        break;
                    }
                    roll -= weight;
                }
            }
        }
    }

    /// @notice Relative weights sum to 100 in each random draw. Background 5 is Genesis-only.
    function traitWeight(uint8 layer, uint8 index) external pure returns (uint256) {
        if (layer == 0 && index == 5) return 100;
        bytes memory weights = _weights(layer);
        if (index >= weights.length) revert InvalidTrait();
        return uint8(weights[index]);
    }

    function traitName(uint8 layer, uint8 index) public view returns (string memory) {
        return _read(_record(layer, index));
    }

    function traitSVG(uint8 layer, uint8 index) public view returns (string memory) {
        return _read(_record(layer, index) + 1);
    }

    function tokenURI(uint256 tokenId, bool isRevealed, uint256 word) external view returns (string memory) {
        _validate(tokenId);
        string memory svg = imageSVG(tokenId, isRevealed, word);
        string memory attributes;
        if (isRevealed) {
            uint8[7] memory selected = traits(tokenId, word);
            for (uint8 i; i < 7; ++i) {
                attributes = string.concat(
                    attributes, i == 0 ? "" : ",", _attribute(_category(i), traitName(i, selected[i]))
                );
            }
            attributes = string.concat(
                attributes,
                ",",
                _attribute("Edition", tokenId <= 77 ? "Genesis" : "Night Crew"),
                ",",
                _attribute("Signature", tokenId == 1 ? "Zero-Sleep Captain / 1 of 1" : "Crew Issue")
            );
        } else {
            attributes = _attribute("Status", "Awaiting first watch");
        }
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"NIGHT FROGS #',
                        tokenId.toString(),
                        '","description":"The 3 AM crew of NIGHTSHIFT, the autonomous AI company platform on the IMD swarm. Tired, caffeinated, a little dangerous. Founders sleep. We ship. Original art, forever onchain.","image":"data:image/svg+xml;base64,',
                        Base64.encode(bytes(svg)),
                        '","attributes":[',
                        attributes,
                        "]}"
                    )
                )
            )
        );
    }

    function imageSVG(uint256 tokenId, bool isRevealed, uint256 word)
        public
        view
        returns (string memory svg)
    {
        _validate(tokenId);
        uint8[7] memory selected = traits(tokenId, word);
        string memory accent = isRevealed ? _accent(selected[0]) : "#C4B4FF";
        svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000" color="',
            accent,
            '"><title>NIGHT FROGS #',
            tokenId.toString(),
            "</title>",
            _read(0)
        );
        if (isRevealed) {
            for (uint8 i; i < 7; ++i) {
                svg = string.concat(svg, traitSVG(i, selected[i]));
            }
            if (selected[6] == 1) {
                svg = string.concat(
                    svg,
                    '<text x="500" y="858" font-size="23" fill="#08070D" text-anchor="middle">#',
                    tokenId.toString(),
                    "</text>"
                );
            }
            if (tokenId == 1) svg = string.concat(svg, _read(3));
        } else {
            svg = string.concat(svg, _read(2));
        }
        return string.concat(
            svg,
            _read(1),
            '<text x="500" y="938" font-size="25" fill="#FFC46B" text-anchor="middle">#',
            tokenId.toString(),
            "</text></svg>"
        );
    }

    function _read(uint256 record) internal view returns (string memory) {
        return record < 19 ? art1.read(record) : art2.read(record - 19);
    }

    function _record(uint8 layer, uint8 index) internal pure returns (uint256) {
        uint8[7] memory counts = [6, 6, 8, 6, 8, 8, 6];
        uint8[7] memory offsets = [4, 16, 28, 44, 56, 72, 88];
        if (layer >= 7 || index >= counts[layer]) revert InvalidTrait();
        return offsets[layer] + uint256(index) * 2;
    }

    function _weights(uint8 layer) internal pure returns (bytes memory) {
        if (layer == 0) return hex"1e1414140a"; // 30,20,20,20,10
        if (layer == 1) return hex"1e17120f0b03"; // 30,23,18,15,11,3
        if (layer == 2) return hex"23140f050a0a0401"; // 35,20,15,5,10,10,4,1
        if (layer == 3) return hex"1c140f0c1207"; // 28,20,15,12,18,7
        if (layer == 4) return hex"260710080c0a0702"; // 38,7,16,8,12,10,7,2
        if (layer == 5) return hex"141411031108010e"; // 20,20,17,3,17,8,1,14
        if (layer == 6) return hex"0f161b0e080e"; // 15,22,27,14,8,14
        revert InvalidTrait();
    }

    function _category(uint8 layer) internal pure returns (string memory) {
        if (layer == 0) return "Background";
        if (layer == 1) return "Body";
        if (layer == 2) return "Skin";
        if (layer == 3) return "Mouth";
        if (layer == 4) return "Eyes";
        if (layer == 5) return "Headwear";
        return "Accessory";
    }

    function _accent(uint8 background) internal pure returns (string memory) {
        if (background == 1) return "#7C5CFF";
        if (background == 2) return "#C4B4FF";
        if (background == 4) return "#B8FF4A";
        if (background == 5) return "#FFC46B";
        return "#3FE6FF";
    }

    function _attribute(string memory category, string memory value) internal pure returns (string memory) {
        // Both strings are immutable, authored ASCII; never user-controlled JSON.
        return string.concat('{"trait_type":"', category, '","value":"', value, '"}');
    }

    function _validate(uint256 tokenId) internal pure {
        if (tokenId == 0 || tokenId > 500) revert InvalidTokenId();
    }
}
