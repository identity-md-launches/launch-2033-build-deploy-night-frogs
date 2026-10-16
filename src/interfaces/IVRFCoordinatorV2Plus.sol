// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Chainlink VRF v2.5 subscription request ABI. No coordinator migration authority.
interface IVRFCoordinatorV2Plus {
    struct RandomWordsRequest {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bytes extraArgs;
    }

    function requestRandomWords(RandomWordsRequest calldata request) external returns (uint256 requestId);
}
