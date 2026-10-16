// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixture} from "./helpers/Fixture.sol";
import {console2} from "forge-std/console2.sol";

/// @dev Reproducible documentation fixtures. Seed is exclusively a LOCAL mock fulfillment.
contract PreviewExport is Fixture {
    uint256 internal constant DEMO_WORD = 20261016;

    function testInventory() public view {
        for (uint256 id = 1; id <= 500; ++id) {
            uint8[7] memory selected = renderer.traits(id, DEMO_WORD);
            string memory line = string.concat("TRAITS|", vm.toString(id));
            for (uint8 i; i < 7; ++i) {
                line = string.concat(line, "|", vm.toString(selected[i]));
            }
            console2.log(line);
        }
    }

    function testExport() public {
        _sellOut();
        _request();
        _fulfill(DEMO_WORD);
        uint16[16] memory ids = [1, 2, 77, 78, 79, 80, 81, 82, 83, 84, 112, 113, 131, 187, 224, 500];
        for (uint256 i; i < ids.length; ++i) {
            string memory uri = nft.tokenURI(ids[i]);
            assertGt(bytes(uri).length, 1000);
            console2.log(string.concat("PREVIEW|", vm.toString(ids[i]), "|", uri));
        }
        console2.log(string.concat("MOON|1|", renderer.tokenURI(1, false, 0)));
    }
}
