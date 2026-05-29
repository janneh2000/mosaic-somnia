// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {AgentRegistry} from "./AgentRegistry.sol";
import {ReputationLedger} from "./ReputationLedger.sol";
import {ISomniaAgents, ISomniaAgentsCallback} from "./interfaces/ISomniaAgents.sol";

/// @title  MosaicHub
/// @notice Composable entrypoint for invoking any agent registered in
///         the Mosaic marketplace. Routes NATIVE invocations to Somnia's
///         validator-consensus platform, and emits IntentCreated for
///         EXTERNAL invocations to be fulfilled by off-chain runners.
contract MosaicHub is Ownable2Step, Pausable, ReentrancyGuard, ISomniaAgentsCallback {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /* ----------------------------- types ----------------------------- */

    enum InvocationStatus {
        Pending,
        Fulfilled,
        Failed,
        TimedOut,
        Refunded
    }

    struct Invocation {
        uint256 agentId;
        address caller;
        address callbackContract;
        bytes4 callbackSelector;
        uint256 feeEscrowed; // STT held for agent owner on success
        uint128 createdAt; // block.timestamp (ms granularity = *1000)
        InvocationStatus status;
        // For NATIVE invocations the Hub records the Somnia platform request id
        // here so it can correlate the platform callback to our invocationId.
        uint256 somniaRequestId;
    }

    /* ----------------------------- state ----------------------------- */

    AgentRegistry public immutable registry;
    ReputationLedger public immutable reputation;
    ISomniaAgents public immutable somnia;

    /// @notice optional native-STT bonus on top of getRequestDeposit() to ensure
    ///         the per-agent reward is competitive. Owner-tunable.
    uint256 public nativePerAgentReward = 0.03 ether; // matches docs JSON_FETCH price
    /// @notice Somnia subcommittee size used for the basic createRequest path.
    uint256 public constant SUBCOMMITTEE_SIZE = 3;

    /// @notice basis-points protocol fee (0..1000 = 0..10%). Owner-tunable.
    uint16 public protocolFeeBps = 0;
    /// @notice address protocol fees accrue to.
    address public treasury;

    uint256 public nextInvocationId = 1;
    mapping(uint256 => Invocation) public invocations;
    mapping(uint256 => uint256) public somniaIdToInvocation;
    mapping(address => uint256) public withdrawable;

    /// @notice Struct-returning getter (auto-getter returns an 8-tuple which
    ///         can blow stack on naive callers).
    function getInvocation(uint256 id) external view returns (Invocation memory) {
        return invocations[id];
    }

    /* ----------------------------- events ---------------------------- */

    event IntentCreated(
        uint256 indexed invocationId,
        uint256 indexed agentId,
        address indexed caller,
        bytes payload,
        uint256 fee,
        uint256 nonce
    );

    event NativeRequestForwarded(
        uint256 indexed invocationId,
        uint256 indexed agentId,
        uint256 somniaRequestId,
        uint256 deposit
    );

    event InvocationFulfilled(
        uint256 indexed invocationId,
        uint256 indexed agentId,
        InvocationStatus status,
        uint128 latencyMs
    );

    event Withdraw(address indexed who, uint256 amount);
    event ProtocolFeeUpdated(uint16 bps);
    event TreasuryUpdated(address treasury);
    event NativeRewardUpdated(uint256 reward);

    /* ----------------------------- errors ---------------------------- */

    error AgentInactive();
    error UnknownAgent();
    error WrongAgentType();
    error InsufficientFee();
    error UnknownInvocation();
    error AlreadySettled();
    error BadSignature();
    error CallbackFailed();
    error NotPlatform();
    error ZeroAddress();
    error WithdrawFailed();
    error FeeTooHigh();

    /* --------------------------- constructor ------------------------- */

    constructor(
        address initialOwner,
        AgentRegistry registry_,
        ReputationLedger reputation_,
        ISomniaAgents somnia_,
        address treasury_
    ) Ownable(initialOwner) {
        if (treasury_ == address(0)) revert ZeroAddress();
        registry = registry_;
        reputation = reputation_;
        somnia = somnia_;
        treasury = treasury_;
    }

    /* -------------------------- invocations -------------------------- */

    /// @notice Invoke any agent registered in the marketplace.
    ///         For EXTERNAL agents: caller pays agent.pricePerInvocation (+ protocol fee).
    ///         For NATIVE agents:  caller pays agent.pricePerInvocation + Somnia deposit.
    /// @param  agentId           Mosaic agent id (from AgentRegistry).
    /// @param  payload           Opaque bytes passed to the agent.
    /// @param  callbackContract  Contract to receive the result callback.
    /// @param  callbackSelector  4-byte selector of `function(uint256,bytes,uint8)` on that contract.
    function invoke(
        uint256 agentId,
        bytes calldata payload,
        address callbackContract,
        bytes4 callbackSelector
    ) external payable whenNotPaused nonReentrant returns (uint256 invocationId) {
        AgentRegistry.Agent memory a = registry.getAgent(agentId);
        if (!a.active) revert AgentInactive();
        if (callbackContract == address(0)) revert ZeroAddress();

        invocationId = nextInvocationId++;
        uint256 protocolFee = (a.pricePerInvocation * protocolFeeBps) / 10_000;

        if (a.agentType == AgentRegistry.AgentType.EXTERNAL) {
            _invokeExternal(
                invocationId,
                agentId,
                a.pricePerInvocation,
                protocolFee,
                payload,
                callbackContract,
                callbackSelector
            );
        } else {
            _invokeNative(
                invocationId,
                agentId,
                a.nativeAgentId,
                a.pricePerInvocation,
                protocolFee,
                payload,
                callbackContract,
                callbackSelector
            );
        }
    }

    function _invokeExternal(
        uint256 invocationId,
        uint256 agentId,
        uint256 agentFee,
        uint256 protocolFee,
        bytes calldata payload,
        address callbackContract,
        bytes4 callbackSelector
    ) internal {
        uint256 required = agentFee + protocolFee;
        if (msg.value < required) revert InsufficientFee();

        invocations[invocationId] = Invocation({
            agentId: agentId,
            caller: msg.sender,
            callbackContract: callbackContract,
            callbackSelector: callbackSelector,
            feeEscrowed: agentFee,
            createdAt: uint128(block.timestamp),
            status: InvocationStatus.Pending,
            somniaRequestId: 0
        });

        if (protocolFee > 0) withdrawable[treasury] += protocolFee;
        _refundOverpay(required);

        emit IntentCreated(invocationId, agentId, msg.sender, payload, agentFee, invocationId);
    }

    function _invokeNative(
        uint256 invocationId,
        uint256 agentId,
        uint256 nativeAgentId,
        uint256 agentFee,
        uint256 protocolFee,
        bytes calldata payload,
        address callbackContract,
        bytes4 callbackSelector
    ) internal {
        uint256 somniaDeposit =
            somnia.getRequestDeposit() + (nativePerAgentReward * SUBCOMMITTEE_SIZE);
        if (msg.value < agentFee + protocolFee + somniaDeposit) revert InsufficientFee();

        uint256 somniaRequestId = somnia.createRequest{value: somniaDeposit}(
            nativeAgentId, address(this), this.handleResponse.selector, payload
        );

        invocations[invocationId] = Invocation({
            agentId: agentId,
            caller: msg.sender,
            callbackContract: callbackContract,
            callbackSelector: callbackSelector,
            feeEscrowed: agentFee,
            createdAt: uint128(block.timestamp),
            status: InvocationStatus.Pending,
            somniaRequestId: somniaRequestId
        });
        somniaIdToInvocation[somniaRequestId] = invocationId;

        if (protocolFee > 0) withdrawable[treasury] += protocolFee;
        _refundOverpay(agentFee + protocolFee + somniaDeposit);

        emit NativeRequestForwarded(invocationId, agentId, somniaRequestId, somniaDeposit);
    }

    function _refundOverpay(uint256 required) internal {
        uint256 overpay = msg.value - required;
        if (overpay > 0) {
            (bool ok,) = payable(msg.sender).call{value: overpay}("");
            if (!ok) revert WithdrawFailed();
        }
    }

    /* --------------------- external fulfillment --------------------- */

    /// @notice Fulfill an external agent invocation.
    ///         The signature must be over keccak256(abi.encode(address(this), invocationId, result))
    ///         and signed by the agent's owner (as recorded in AgentRegistry).
    ///         Either the agent owner or anyone holding a valid signature may submit.
    function fulfillIntent(uint256 invocationId, bytes calldata result, bytes calldata signature)
        external
        whenNotPaused
        nonReentrant
    {
        Invocation storage inv = invocations[invocationId];
        if (inv.caller == address(0)) revert UnknownInvocation();
        if (inv.status != InvocationStatus.Pending) revert AlreadySettled();

        AgentRegistry.Agent memory a = registry.getAgent(inv.agentId);
        if (a.agentType != AgentRegistry.AgentType.EXTERNAL) revert WrongAgentType();

        bytes32 digest =
            keccak256(abi.encode(address(this), invocationId, result)).toEthSignedMessageHash();
        address signer = digest.recover(signature);
        if (signer != a.owner) revert BadSignature();

        _settleSuccess(invocationId, inv, a.owner, result);
    }

    /// @notice Allow the original caller (or the agent owner) to mark an external
    ///         invocation as failed and reclaim the fee. Useful if the runner is offline.
    ///         Only callable after a 1-hour grace window.
    function refundExpired(uint256 invocationId) external nonReentrant {
        Invocation storage inv = invocations[invocationId];
        if (inv.caller == address(0)) revert UnknownInvocation();
        if (inv.status != InvocationStatus.Pending) revert AlreadySettled();
        AgentRegistry.Agent memory a = registry.getAgent(inv.agentId);
        require(
            msg.sender == inv.caller || msg.sender == a.owner || msg.sender == owner(),
            "not authorized"
        );
        require(block.timestamp >= inv.createdAt + 1 hours, "not expired");

        inv.status = InvocationStatus.Refunded;
        withdrawable[inv.caller] += inv.feeEscrowed;
        inv.feeEscrowed = 0;
        uint128 latency = _latency(inv.createdAt);
        reputation.record(inv.agentId, ReputationLedger.Outcome.Timeout, latency);

        // Notify the consumer's callback so e.g. GuardianModule can produce
        // an on-chain-only report when the off-chain runner never showed up.
        (bool ok,) = inv.callbackContract.call(
            abi.encodeWithSelector(
                inv.callbackSelector, invocationId, bytes(""), InvocationStatus.TimedOut
            )
        );
        ok; // intentionally ignored

        emit InvocationFulfilled(invocationId, inv.agentId, InvocationStatus.TimedOut, latency);
    }

    /* ---------------------- native callback path -------------------- */

    /// @inheritdoc ISomniaAgentsCallback
    function handleResponse(
        uint256 requestId,
        ISomniaAgents.Response[] memory responses,
        ISomniaAgents.ResponseStatus status,
        ISomniaAgents.Request memory /* details */
    ) external override {
        if (msg.sender != address(somnia)) revert NotPlatform();
        uint256 invocationId = somniaIdToInvocation[requestId];
        if (invocationId == 0) revert UnknownInvocation();
        Invocation storage inv = invocations[invocationId];
        if (inv.status != InvocationStatus.Pending) revert AlreadySettled();
        delete somniaIdToInvocation[requestId];

        AgentRegistry.Agent memory a = registry.getAgent(inv.agentId);

        if (status == ISomniaAgents.ResponseStatus.Success && responses.length > 0) {
            // Use first response's result bytes (Majority consensus guarantees identical bytes
            // across at least `threshold` validators).
            _settleSuccess(invocationId, inv, a.owner, responses[0].result);
        } else if (status == ISomniaAgents.ResponseStatus.TimedOut) {
            _settleFailure(invocationId, inv, InvocationStatus.TimedOut);
        } else {
            _settleFailure(invocationId, inv, InvocationStatus.Failed);
        }
    }

    /* ---------------------------- payouts ---------------------------- */

    function withdraw() external nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "nothing to withdraw");
        withdrawable[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit Withdraw(msg.sender, amount);
    }

    /// @dev allow receiving Somnia rebates
    receive() external payable {}

    /* ---------------------------- admin ------------------------------ */

    function setProtocolFee(uint16 bps) external onlyOwner {
        if (bps > 1000) revert FeeTooHigh(); // hard cap 10%
        protocolFeeBps = bps;
        emit ProtocolFeeUpdated(bps);
    }

    function setTreasury(address t) external onlyOwner {
        if (t == address(0)) revert ZeroAddress();
        treasury = t;
        emit TreasuryUpdated(t);
    }

    function setNativePerAgentReward(uint256 r) external onlyOwner {
        nativePerAgentReward = r;
        emit NativeRewardUpdated(r);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* --------------------------- internal ---------------------------- */

    function _settleSuccess(
        uint256 invocationId,
        Invocation storage inv,
        address agentOwner,
        bytes memory result
    ) internal {
        inv.status = InvocationStatus.Fulfilled;
        withdrawable[agentOwner] += inv.feeEscrowed;
        uint256 fee = inv.feeEscrowed;
        inv.feeEscrowed = 0;

        uint128 latency = _latency(inv.createdAt);
        reputation.record(inv.agentId, ReputationLedger.Outcome.Success, latency);

        // Forward result to caller's callback contract. Failure of the
        // user's callback must NOT undo the payout — agents shouldn't be
        // punished for buggy consumers.
        (bool ok,) = inv.callbackContract.call(
            abi.encodeWithSelector(
                inv.callbackSelector, invocationId, result, InvocationStatus.Fulfilled
            )
        );
        // ok is intentionally ignored (logged externally via event)
        ok; // silence unused

        emit InvocationFulfilled(invocationId, inv.agentId, InvocationStatus.Fulfilled, latency);
        // silence the unused-fee warning
        fee;
    }

    function _settleFailure(
        uint256 invocationId,
        Invocation storage inv,
        InvocationStatus failStatus
    ) internal {
        inv.status = failStatus;
        // Return escrow to caller
        withdrawable[inv.caller] += inv.feeEscrowed;
        inv.feeEscrowed = 0;

        uint128 latency = _latency(inv.createdAt);
        ReputationLedger.Outcome outcome = failStatus == InvocationStatus.TimedOut
            ? ReputationLedger.Outcome.Timeout
            : ReputationLedger.Outcome.Failure;
        reputation.record(inv.agentId, outcome, latency);

        // Notify caller of failure (no result bytes)
        (bool ok,) = inv.callbackContract.call(
            abi.encodeWithSelector(inv.callbackSelector, invocationId, bytes(""), failStatus)
        );
        ok; // silence unused

        emit InvocationFulfilled(invocationId, inv.agentId, failStatus, latency);
    }

    function _latency(uint128 createdAt) internal view returns (uint128) {
        // Seconds * 1000 — close-enough ms; sub-second granularity not available on EVM
        return uint128((block.timestamp - createdAt) * 1000);
    }
}
