// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MosaicHub} from "./MosaicHub.sol";
import {AgentRegistry} from "./AgentRegistry.sol";

/// @title  GuardianModule
/// @notice Mosaic's flagship security agent. Performs an on-chain heuristic
///         scan of any target contract and (optionally) combines it with an
///         off-chain analysis posted by a runner via the marketplace's
///         external-agent fulfillment path.
/// @dev    Self-registers as an EXTERNAL agent in AgentRegistry at deploy.
contract GuardianModule {
    /* ----------------------------- types ----------------------------- */

    struct ScanReport {
        address target;
        uint256 codeSize;
        bool hasSelfdestruct;
        bool hasDelegatecall;
        uint8 onchainRiskScore; // 0..100
        uint8 offchainRiskScore; // 0..100; 255 = unavailable
        uint8 compositeRiskScore; // 0..100
        uint256 generatedAt;
        bytes offchainDetails; // free-form bytes from off-chain runner
    }

    /* ----------------------------- state ----------------------------- */

    MosaicHub public immutable hub;
    AgentRegistry public immutable registry;

    /// @notice Agent id of Guardian in the AgentRegistry.
    uint256 public guardianAgentId;

    /// @notice last completed report per target.
    mapping(address => ScanReport) public lastReport;

    /// @notice Struct-returning view for off-chain callers that want the
    ///         entire report in one read (the auto-getter returns a 9-tuple
    ///         which can blow stack on naive consumers).
    function getLastReport(address target) external view returns (ScanReport memory) {
        return lastReport[target];
    }
    /// @notice invocationId => target being scanned
    mapping(uint256 => address) public pendingScans;

    /* ---------------------------- events ----------------------------- */

    event ScanRequested(uint256 indexed invocationId, address indexed target, address requester);
    event ScanCompleted(address indexed target, uint8 composite, ScanReport report);

    /* ---------------------------- errors ----------------------------- */

    error AlreadyRegistered();
    error NotHub();

    /* --------------------------- constructor ------------------------- */

    constructor(MosaicHub hub_, AgentRegistry registry_) {
        hub = hub_;
        registry = registry_;
    }

    /// @notice Self-register Guardian as an external agent (called once at setup).
    /// @dev    Owner of the registered agent will be address(this). A contract
    ///         cannot sign EIP-191 messages, so use selfRegisterAndTransfer
    ///         below if you want an off-chain runner wallet to fulfill scans.
    function selfRegister(uint256 pricePerInvocation, string calldata metadataURI)
        external
        returns (uint256)
    {
        if (guardianAgentId != 0) revert AlreadyRegistered();
        guardianAgentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL,
            0,
            pricePerInvocation,
            metadataURI,
            "security"
        );
        return guardianAgentId;
    }

    /// @notice Self-register Guardian and immediately transfer the agent record
    ///         to `runnerOwner`, so that runnerOwner's wallet can sign valid
    ///         fulfillments via MosaicHub.fulfillIntent.
    ///         This is the function the deploy script should call in any
    ///         deployment that uses an off-chain Guardian runner.
    function selfRegisterAndTransfer(
        uint256 pricePerInvocation,
        string calldata metadataURI,
        address runnerOwner
    ) external returns (uint256) {
        if (guardianAgentId != 0) revert AlreadyRegistered();
        require(runnerOwner != address(0), "runnerOwner=0");
        guardianAgentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL,
            0,
            pricePerInvocation,
            metadataURI,
            "security"
        );
        // GuardianModule is the temporary owner (set by register()); transfer
        // to the runner wallet so it can sign personal-sign fulfillments.
        registry.transferAgent(guardianAgentId, runnerOwner);
        return guardianAgentId;
    }

    /* --------------------------- scanning ---------------------------- */

    /// @notice Anyone can request a Guardian scan of a target contract.
    ///         Caller pays the per-invocation fee for Guardian (set in registry).
    ///         The composite risk score is computed and stored when the off-chain
    ///         runner posts results back through the marketplace.
    function requestScan(address target) external payable returns (uint256 invocationId) {
        bytes memory payload = abi.encode(target);
        invocationId = hub.invoke{value: msg.value}(
            guardianAgentId, payload, address(this), this.onScanResult.selector
        );
        pendingScans[invocationId] = target;
        emit ScanRequested(invocationId, target, msg.sender);
    }

    /// @notice MosaicHub forwards results here. Combines off-chain bytes with
    ///         a fresh on-chain heuristic to produce a composite risk score.
    function onScanResult(uint256 invocationId, bytes calldata result, uint8 status) external {
        if (msg.sender != address(hub)) revert NotHub();
        address target = pendingScans[invocationId];
        if (target == address(0)) return; // unknown
        delete pendingScans[invocationId];

        // On-chain heuristic: a real scanner would inspect bytecode further; we
        // keep this minimal but verifiable.
        (uint256 size, bool sd, bool dc) = _bytecodeHeuristic(target);
        uint8 onchain = _onchainScore(size, sd, dc);

        uint8 offchain = 255; // unavailable by default
        bytes memory offchainBytes = "";
        // status == 1 == Fulfilled (mirrors MosaicHub.InvocationStatus.Fulfilled)
        if (status == 1 && result.length > 0) {
            // Off-chain runner returns abi.encode(uint8 score, bytes details)
            (uint8 score, bytes memory details) = abi.decode(result, (uint8, bytes));
            offchain = score;
            offchainBytes = details;
        }

        uint8 composite =
            offchain == 255 ? onchain : uint8((uint16(onchain) + uint16(offchain)) / 2);

        ScanReport memory report = ScanReport({
            target: target,
            codeSize: size,
            hasSelfdestruct: sd,
            hasDelegatecall: dc,
            onchainRiskScore: onchain,
            offchainRiskScore: offchain,
            compositeRiskScore: composite,
            generatedAt: block.timestamp,
            offchainDetails: offchainBytes
        });
        lastReport[target] = report;
        emit ScanCompleted(target, composite, report);
    }

    /* --------------------------- heuristics -------------------------- */

    function _bytecodeHeuristic(address target)
        internal
        view
        returns (uint256 size, bool hasSelfdestruct, bool hasDelegatecall)
    {
        size = target.code.length;
        if (size == 0) return (0, false, false);

        // Scan for SELFDESTRUCT (0xff) and DELEGATECALL (0xf4) opcodes.
        // Naive linear scan; OK for testnet-scale targets.
        bytes memory code = target.code;
        for (uint256 i; i < code.length; ++i) {
            bytes1 op = code[i];
            if (op == bytes1(0xff)) hasSelfdestruct = true;
            else if (op == bytes1(0xf4)) hasDelegatecall = true;
            if (hasSelfdestruct && hasDelegatecall) break;
        }
    }

    function _onchainScore(uint256 size, bool sd, bool dc) internal pure returns (uint8) {
        // Risk model (intentionally simple, intentionally explainable):
        //   base 10
        //   +30 if contains SELFDESTRUCT
        //   +20 if contains DELEGATECALL
        //   +10 if code is tiny (< 200 bytes) — likely a minimal proxy
        // capped at 100.
        uint16 score = 10;
        if (sd) score += 30;
        if (dc) score += 20;
        if (size > 0 && size < 200) score += 10;
        if (score > 100) score = 100;
        return uint8(score);
    }
}
