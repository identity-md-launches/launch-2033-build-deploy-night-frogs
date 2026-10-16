// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev SSTORE2 payload: STOP followed by immutable data. Calling it cannot execute its data.
contract FrogData {
    constructor(bytes memory data) {
        require(data.length <= 24_575, "art exceeds EIP-170");
        bytes memory runtime = bytes.concat(hex"00", data);
        assembly ("memory-safe") {
            return(add(runtime, 32), mload(runtime))
        }
    }
}

/// @dev Packed records: uint16 count, count+1 uint16 offsets, then UTF-8 strings.
abstract contract ArtStore {
    address public immutable dataPointer;
    uint256 public immutable recordCount;

    error InvalidRecord();

    constructor(bytes memory data, uint256 count) {
        dataPointer = address(new FrogData(data));
        recordCount = count;
    }

    function read(uint256 index) external view returns (string memory) {
        if (index >= recordCount) revert InvalidRecord();
        address pointer = dataPointer;
        uint256 offset = 3 + index * 2; // STOP + uint16 count
        uint256 start;
        uint256 end;
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            extcodecopy(pointer, scratch, offset, 4)
            start := shr(240, mload(scratch))
            end := and(shr(224, mload(scratch)), 0xffff)
        }
        bytes memory result = new bytes(end - start);
        assembly ("memory-safe") {
            extcodecopy(pointer, add(result, 32), add(start, 1), sub(end, start))
        }
        return string(result);
    }
}
