// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Captures Mosaic callbacks for tests.
contract CallbackSink {
    struct Got {
        uint256 invocationId;
        bytes result;
        uint8 status;
    }

    Got[] public received;

    function onResult(uint256 invocationId, bytes calldata result, uint8 status) external {
        received.push(Got(invocationId, result, status));
    }

    function count() external view returns (uint256) {
        return received.length;
    }

    function last() external view returns (uint256, bytes memory, uint8) {
        Got memory g = received[received.length - 1];
        return (g.invocationId, g.result, g.status);
    }
}
