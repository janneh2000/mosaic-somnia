// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title  ReputationLedger
/// @notice Tracks verifiable performance counters per agent.
/// @dev    Writable only by the MosaicHub. Read-only for everyone else.
contract ReputationLedger is Ownable2Step {
    struct Stats {
        uint64 totalInvocations;
        uint64 successCount;
        uint64 failureCount;
        uint64 timeoutCount;
        uint128 cumulativeLatencyMs;
        uint128 lastUpdatedAt;
    }

    address public hub;
    mapping(uint256 => Stats) private _stats;

    event HubSet(address indexed hub);
    event StatsUpdated(
        uint256 indexed agentId,
        uint64 totalInvocations,
        uint64 successCount,
        uint64 failureCount,
        uint64 timeoutCount,
        uint128 cumulativeLatencyMs
    );

    error NotHub();
    error InvalidHub();

    enum Outcome {
        Success,
        Failure,
        Timeout
    }

    modifier onlyHub() {
        if (msg.sender != hub) revert NotHub();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice One-time-changeable hub address. Set after MosaicHub is deployed.
    function setHub(address newHub) external onlyOwner {
        if (newHub == address(0)) revert InvalidHub();
        hub = newHub;
        emit HubSet(newHub);
    }

    function record(uint256 agentId, Outcome outcome, uint128 latencyMs) external onlyHub {
        Stats storage s = _stats[agentId];
        unchecked {
            s.totalInvocations += 1;
            if (outcome == Outcome.Success) s.successCount += 1;
            else if (outcome == Outcome.Failure) s.failureCount += 1;
            else s.timeoutCount += 1;
            s.cumulativeLatencyMs += latencyMs;
        }
        s.lastUpdatedAt = uint128(block.timestamp);

        emit StatsUpdated(
            agentId,
            s.totalInvocations,
            s.successCount,
            s.failureCount,
            s.timeoutCount,
            s.cumulativeLatencyMs
        );
    }

    function getStats(uint256 agentId) external view returns (Stats memory) {
        return _stats[agentId];
    }

    /// @notice basis-points success score (0..10000). Returns 0 with no invocations.
    function successRateBps(uint256 agentId) external view returns (uint256) {
        Stats memory s = _stats[agentId];
        if (s.totalInvocations == 0) return 0;
        return (uint256(s.successCount) * 10_000) / uint256(s.totalInvocations);
    }

    function averageLatencyMs(uint256 agentId) external view returns (uint256) {
        Stats memory s = _stats[agentId];
        if (s.totalInvocations == 0) return 0;
        return uint256(s.cumulativeLatencyMs) / uint256(s.totalInvocations);
    }
}
