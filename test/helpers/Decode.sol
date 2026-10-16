// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library Decode {
    // Test-only independent base64 decoder, used to inspect the actual onchain JSON and SVG.
    function dataURI(string memory uri, string memory prefix) internal pure returns (string memory) {
        bytes memory src = bytes(uri);
        bytes memory p = bytes(prefix);
        require(src.length >= p.length && (src.length - p.length) % 4 == 0, "bad data URI");
        for (uint256 i; i < p.length; ++i) {
            require(src[i] == p[i], "bad prefix");
        }
        uint256 size = (src.length - p.length) / 4 * 3;
        if (src[src.length - 1] == "=") --size;
        if (src[src.length - 2] == "=") --size;
        bytes memory out = new bytes(size);
        uint256 cursor;
        for (uint256 i = p.length; i < src.length; i += 4) {
            uint256 v = (value(src[i]) << 18) | (value(src[i + 1]) << 12) | (value(src[i + 2]) << 6)
                | value(src[i + 3]);
            if (cursor < size) out[cursor++] = bytes1(uint8(v >> 16));
            if (cursor < size) out[cursor++] = bytes1(uint8(v >> 8));
            if (cursor < size) out[cursor++] = bytes1(uint8(v));
        }
        return string(out);
    }

    function value(bytes1 c) private pure returns (uint256) {
        uint8 v = uint8(c);
        if (v >= 65 && v <= 90) return v - 65;
        if (v >= 97 && v <= 122) return v - 71;
        if (v >= 48 && v <= 57) return v + 4;
        if (v == 43) return 62;
        if (v == 47) return 63;
        require(v == 61, "bad base64");
        return 0;
    }
}
