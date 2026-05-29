// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {ReputationLedger} from "../src/ReputationLedger.sol";
import {MosaicHub} from "../src/MosaicHub.sol";
import {GuardianModule} from "../src/GuardianModule.sol";
import {ISomniaAgents} from "../src/interfaces/ISomniaAgents.sol";
import {MockSomniaAgents} from "./mocks/MockSomniaAgents.sol";
import {CallbackSink} from "./mocks/CallbackSink.sol";

contract MosaicTest is Test {
    AgentRegistry registry;
    ReputationLedger reputation;
    MosaicHub hub;
    MockSomniaAgents somnia;
    CallbackSink sink;
    GuardianModule guardian;

    address admin = address(0xA11CE);
    address treasury = address(0x7EA);
    address agentOwner;
    uint256 agentOwnerPk = 0xBEEF;

    function setUp() public {
        agentOwner = vm.addr(agentOwnerPk);

        vm.startPrank(admin);
        registry = new AgentRegistry(admin);
        reputation = new ReputationLedger(admin);
        somnia = new MockSomniaAgents();
        hub = new MosaicHub(admin, registry, reputation, ISomniaAgents(address(somnia)), treasury);
        reputation.setHub(address(hub));
        guardian = new GuardianModule(hub, registry);
        guardian.selfRegister(0.05 ether, "ipfs://guardian-meta");
        vm.stopPrank();

        sink = new CallbackSink();

        vm.deal(address(this), 100 ether);
        vm.deal(agentOwner, 100 ether);
    }

    /* ----------------------- registry behavior ----------------------- */

    function test_register_externalAgent() public {
        vm.prank(agentOwner);
        uint256 id = registry.register(
            AgentRegistry.AgentType.EXTERNAL, 0, 0.01 ether, "ipfs://summarizer", "summarizer"
        );
        AgentRegistry.Agent memory a = registry.getAgent(id);
        assertEq(a.owner, agentOwner);
        assertEq(uint8(a.agentType), uint8(AgentRegistry.AgentType.EXTERNAL));
        assertEq(a.pricePerInvocation, 0.01 ether);
        assertTrue(a.active);

        uint256[] memory tagged = registry.agentsByTag("summarizer");
        assertEq(tagged.length, 1);
        assertEq(tagged[0], id);
    }

    function test_register_nativeAgent_requiresNativeId() public {
        vm.prank(agentOwner);
        vm.expectRevert(AgentRegistry.NativeAgentIdRequired.selector);
        registry.register(
            AgentRegistry.AgentType.NATIVE, 0, 0, "ipfs://json", "oracle"
        );
    }

    /* ----------------------- external invocation -------------------- */

    function test_externalInvocation_flow() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL, 0, 0.02 ether, "ipfs://summ", "summarizer"
        );

        // invoke
        uint256 invocationId = hub.invoke{value: 0.02 ether}(
            agentId, bytes("hello"), address(sink), sink.onResult.selector
        );
        assertEq(invocationId, 1);

        // build signature over (hub, invocationId, result)
        bytes memory result = abi.encode("summary: hello-world");
        bytes32 digest = keccak256(abi.encode(address(hub), invocationId, result));
        bytes32 ethDigest =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentOwnerPk, ethDigest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // simulate latency
        vm.warp(block.timestamp + 3);

        hub.fulfillIntent(invocationId, result, sig);

        // callback delivered
        assertEq(sink.count(), 1);
        (uint256 cbId, bytes memory cbResult, uint8 cbStatus) = sink.last();
        assertEq(cbId, invocationId);
        assertEq(cbResult, result);
        assertEq(cbStatus, uint8(MosaicHub.InvocationStatus.Fulfilled));

        // funds withdrawable
        assertEq(hub.withdrawable(agentOwner), 0.02 ether);
        vm.prank(agentOwner);
        hub.withdraw();
        assertEq(hub.withdrawable(agentOwner), 0);

        // reputation
        ReputationLedger.Stats memory st = reputation.getStats(agentId);
        assertEq(st.totalInvocations, 1);
        assertEq(st.successCount, 1);
        assertEq(reputation.successRateBps(agentId), 10_000);
    }

    function test_externalInvocation_badSignatureReverts() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL, 0, 0.02 ether, "ipfs://summ", "summarizer"
        );
        uint256 invocationId = hub.invoke{value: 0.02 ether}(
            agentId, bytes("x"), address(sink), sink.onResult.selector
        );

        bytes memory result = abi.encode("malicious");
        // sign with a different key
        bytes32 digest = keccak256(abi.encode(address(hub), invocationId, result));
        bytes32 ethDigest =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, ethDigest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(MosaicHub.BadSignature.selector);
        hub.fulfillIntent(invocationId, result, sig);
    }

    function test_externalInvocation_refundAfterExpiry() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL, 0, 0.02 ether, "ipfs://summ", "summarizer"
        );
        uint256 invocationId = hub.invoke{value: 0.02 ether}(
            agentId, bytes("x"), address(sink), sink.onResult.selector
        );

        // before expiry: not authorized
        vm.expectRevert("not expired");
        hub.refundExpired(invocationId);

        vm.warp(block.timestamp + 1 hours + 1);
        hub.refundExpired(invocationId);

        // caller has withdrawable balance
        assertEq(hub.withdrawable(address(this)), 0.02 ether);

        // reputation now has a timeout
        ReputationLedger.Stats memory st = reputation.getStats(agentId);
        assertEq(st.timeoutCount, 1);
    }

    /* ----------------------- native invocation ---------------------- */

    function test_nativeInvocation_flow() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.register(
            AgentRegistry.AgentType.NATIVE, 7777, 0.01 ether, "ipfs://oracle", "oracle"
        );

        uint256 somniaDeposit = somnia.getRequestDeposit() + 0.03 ether * 3;
        uint256 required = 0.01 ether + somniaDeposit;
        uint256 invocationId = hub.invoke{value: required}(
            agentId, bytes("BTC"), address(sink), sink.onResult.selector
        );
        assertEq(invocationId, 1);
        MosaicHub.Invocation memory stored = hub.getInvocation(invocationId);
        assertEq(stored.agentId, agentId);
        assertGt(stored.somniaRequestId, 0);
        uint256 somniaReqId = stored.somniaRequestId;

        // simulate Somnia validators reaching consensus
        bytes memory result = abi.encode(uint256(67_500_00000000)); // BTC price w/ 8 decimals
        somnia.deliverSuccess(somniaReqId, result);

        // callback delivered with success status
        assertEq(sink.count(), 1);
        (, , uint8 cbStatus) = sink.last();
        assertEq(cbStatus, uint8(MosaicHub.InvocationStatus.Fulfilled));

        // agent fee credited
        assertEq(hub.withdrawable(agentOwner), 0.01 ether);
    }

    function test_nativeInvocation_timeoutRefunds() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.register(
            AgentRegistry.AgentType.NATIVE, 7777, 0.01 ether, "ipfs://oracle", "oracle"
        );
        uint256 somniaDeposit = somnia.getRequestDeposit() + 0.03 ether * 3;
        uint256 invocationId = hub.invoke{value: 0.01 ether + somniaDeposit}(
            agentId, bytes(""), address(sink), sink.onResult.selector
        );
        uint256 somniaReqId = hub.getInvocation(invocationId).somniaRequestId;

        somnia.deliverTimeout(somniaReqId);

        (, , uint8 status) = sink.last();
        assertEq(status, uint8(MosaicHub.InvocationStatus.TimedOut));
        // caller gets escrow back (fee, not somnia deposit, which is handled by Somnia itself)
        assertEq(hub.withdrawable(address(this)), 0.01 ether);
    }

    /* ----------------------- guardian behavior ---------------------- */

    function test_guardian_onchainOnly() public {
        // Etch a runtime containing both 0xff (SELFDESTRUCT) and 0xf4 (DELEGATECALL)
        // at a deterministic address so the heuristic has something to chew on.
        address target = address(0xC0DE);
        vm.etch(target, hex"ff60f400");

        uint256 invocationId = guardian.requestScan{value: 0.05 ether}(target);

        // No off-chain runner — the agent owner (admin, since Guardian's
        // agent was registered by admin via selfRegister) reclaims the
        // escrow after the 1-hour expiry. refundExpired dispatches a
        // TimedOut callback to GuardianModule, which still computes the
        // on-chain-only score from the etched bytecode.
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(admin);
        hub.refundExpired(invocationId);

        GuardianModule.ScanReport memory r = guardian.getLastReport(target);
        assertGt(r.codeSize, 0);
        // base 10 + 30 (SELFDESTRUCT) + 20 (DELEGATECALL) + 10 (size<200) = 70
        assertEq(r.onchainRiskScore, 70);
        assertEq(r.offchainRiskScore, 255);
        assertEq(r.compositeRiskScore, 70);
    }

    /* ------------------------- pull payment ------------------------- */

    function test_withdraw_zero_reverts() public {
        vm.expectRevert(bytes("nothing to withdraw"));
        hub.withdraw();
    }
}
