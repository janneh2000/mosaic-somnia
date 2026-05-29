// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISomniaAgents
/// @notice Minimal interface to the Somnia Agents platform contract.
/// @dev Mirrors the public ABI documented at
///      https://docs.somnia.network/agents/invoking-agents/from-solidity
///      so Mosaic can route invocations to validator-consensus agents.
///      Testnet address: 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776
///      Mainnet address: 0x5E5205CF39E766118C01636bED000A54D93163E6
interface ISomniaAgents {
    enum ConsensusType {
        Majority,
        Threshold
    }

    enum ResponseStatus {
        None,
        Pending,
        Success,
        Failed,
        TimedOut
    }

    struct Response {
        address validator;
        bytes result;
        ResponseStatus status;
        uint256 receipt;
        uint256 timestamp;
        uint256 executionCost;
    }

    struct Request {
        uint256 id;
        address requester;
        address callbackAddress;
        bytes4 callbackSelector;
        address[] subcommittee;
        Response[] responses;
        uint256 responseCount;
        uint256 failureCount;
        uint256 threshold;
        uint256 createdAt;
        uint256 deadline;
        ResponseStatus status;
        ConsensusType consensusType;
        uint256 remainingBudget;
        uint256 perAgentBudget;
    }

    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable returns (uint256 requestId);

    function getRequestDeposit() external view returns (uint256);
}

/// @notice The shape every Somnia-Agents callback must implement.
interface ISomniaAgentsCallback {
    function handleResponse(
        uint256 requestId,
        ISomniaAgents.Response[] memory responses,
        ISomniaAgents.ResponseStatus status,
        ISomniaAgents.Request memory details
    ) external;
}
