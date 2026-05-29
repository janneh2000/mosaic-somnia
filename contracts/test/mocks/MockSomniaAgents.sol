// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISomniaAgents, ISomniaAgentsCallback} from "../../src/interfaces/ISomniaAgents.sol";

/// @notice Deterministic mock of the SomniaAgents platform for tests.
contract MockSomniaAgents is ISomniaAgents {
    uint256 public nextId = 1;
    uint256 public depositRequired = 0.01 ether;

    struct Stored {
        address callbackAddress;
        bytes4 selector;
        uint256 deposit;
    }

    mapping(uint256 => Stored) public stored;

    function setDeposit(uint256 d) external {
        depositRequired = d;
    }

    function getRequestDeposit() external view returns (uint256) {
        return depositRequired;
    }

    function createRequest(
        uint256, /* agentId */
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata /* payload */
    ) external payable returns (uint256 requestId) {
        require(msg.value >= depositRequired, "deposit too low");
        requestId = nextId++;
        stored[requestId] = Stored(callbackAddress, callbackSelector, msg.value);
    }

    /// @notice helper to simulate validator consensus completing.
    function deliverSuccess(uint256 requestId, bytes calldata result) external {
        Stored memory s = stored[requestId];
        require(s.callbackAddress != address(0), "unknown");
        delete stored[requestId];

        Response[] memory rs = new Response[](3);
        for (uint256 i; i < 3; ++i) {
            rs[i] = Response({
                validator: address(uint160(0xA0 + i)),
                result: result,
                status: ResponseStatus.Success,
                receipt: 0,
                timestamp: block.timestamp,
                executionCost: 0
            });
        }
        Request memory req;
        req.id = requestId;
        req.responses = rs;
        req.responseCount = 3;
        req.threshold = 2;
        req.status = ResponseStatus.Success;
        ISomniaAgentsCallback(s.callbackAddress).handleResponse(
            requestId, rs, ResponseStatus.Success, req
        );
    }

    function deliverTimeout(uint256 requestId) external {
        Stored memory s = stored[requestId];
        require(s.callbackAddress != address(0), "unknown");
        delete stored[requestId];
        Response[] memory rs = new Response[](0);
        Request memory req;
        req.id = requestId;
        req.status = ResponseStatus.TimedOut;
        ISomniaAgentsCallback(s.callbackAddress).handleResponse(
            requestId, rs, ResponseStatus.TimedOut, req
        );
    }

    receive() external payable {}
}
