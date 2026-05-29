// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {AgentRegistry} from "../src/AgentRegistry.sol";
import {ReputationLedger} from "../src/ReputationLedger.sol";
import {MosaicHub} from "../src/MosaicHub.sol";
import {GuardianModule} from "../src/GuardianModule.sol";
import {ISomniaAgents} from "../src/interfaces/ISomniaAgents.sol";
import {MockSomniaAgents} from "./mocks/MockSomniaAgents.sol";
import {CallbackSink} from "./mocks/CallbackSink.sol";

/// @notice Gap-coverage suite. Complements Mosaic.t.sol (happy paths) by
///         exercising the non-obvious patterns the architecture relies on:
///         selfRegisterAndTransfer, zero-address guards, agent transfer,
///         soft-delete, pausing, protocol fees, and access control.
contract MosaicExtraTest is Test {
    AgentRegistry registry;
    ReputationLedger reputation;
    MosaicHub hub;
    MockSomniaAgents somnia;
    CallbackSink sink;
    GuardianModule guardian;

    address admin = address(0xA11CE);
    address treasury = address(0x7EA);
    address bob = address(0xB0B);

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
        vm.deal(bob, 100 ether);
    }

    /// @dev helper: register a basic active EXTERNAL agent owned by agentOwner.
    function _registerExternal(uint256 price) internal returns (uint256 id) {
        vm.prank(agentOwner);
        id = registry.register(
            AgentRegistry.AgentType.EXTERNAL, 0, price, "ipfs://meta", "summarizer"
        );
    }

    /* ------------------- selfRegisterAndTransfer -------------------- */

    function test_selfRegisterAndTransfer_setsRunnerAsOwner() public {
        // Fresh module so guardianAgentId is unset.
        GuardianModule g2 = new GuardianModule(hub, registry);
        uint256 id = g2.selfRegisterAndTransfer(0.05 ether, "ipfs://g2", agentOwner);

        AgentRegistry.Agent memory a = registry.getAgent(id);
        // Ownership must land on the runner wallet (an EOA that can sign), not
        // the contract that registered it.
        assertEq(a.owner, agentOwner);
        assertEq(a.capabilityTag, "security");
        assertEq(g2.guardianAgentId(), id);
    }

    function test_selfRegisterAndTransfer_revertsOnZeroRunner() public {
        GuardianModule g2 = new GuardianModule(hub, registry);
        vm.expectRevert(bytes("runnerOwner=0"));
        g2.selfRegisterAndTransfer(0.05 ether, "ipfs://g2", address(0));
    }

    function test_selfRegister_revertsIfAlreadyRegistered() public {
        // setUp already registered the main guardian via selfRegister.
        vm.expectRevert(GuardianModule.AlreadyRegistered.selector);
        guardian.selfRegisterAndTransfer(0.05 ether, "ipfs://x", agentOwner);
    }

    /* --------------------- invoke input guards ---------------------- */

    function test_invoke_revertsOnZeroCallback() public {
        uint256 id = _registerExternal(0.01 ether);
        vm.expectRevert(MosaicHub.ZeroAddress.selector);
        hub.invoke{value: 0.01 ether}(id, bytes("x"), address(0), sink.onResult.selector);
    }

    function test_invoke_revertsOnUnknownAgent() public {
        vm.expectRevert(AgentRegistry.UnknownAgent.selector);
        hub.invoke{value: 0.01 ether}(999, bytes("x"), address(sink), sink.onResult.selector);
    }

    function test_invoke_revertsOnInsufficientFee() public {
        uint256 id = _registerExternal(0.02 ether);
        vm.expectRevert(MosaicHub.InsufficientFee.selector);
        hub.invoke{value: 0.01 ether}(id, bytes("x"), address(sink), sink.onResult.selector);
    }

    function test_invoke_refundsOverpay() public {
        uint256 id = _registerExternal(0.02 ether);
        uint256 balBefore = address(this).balance;
        hub.invoke{value: 1 ether}(id, bytes("x"), address(sink), sink.onResult.selector);
        // Only the 0.02 fee should be consumed; the rest is refunded inline.
        assertEq(address(this).balance, balBefore - 0.02 ether);
    }

    /* ----------------------- soft-delete flow ----------------------- */

    function test_softDelete_hidesAndBlocksInvoke() public {
        uint256 id = _registerExternal(0.01 ether);

        // "Delete" = update(active=false). Keeps the record + reputation history.
        vm.prank(agentOwner);
        registry.update(id, 0.01 ether, "ipfs://meta", false);

        AgentRegistry.Agent memory a = registry.getAgent(id);
        assertFalse(a.active);

        // Marketplace hides it (frontend filters active), and invoke is blocked.
        vm.expectRevert(MosaicHub.AgentInactive.selector);
        hub.invoke{value: 0.01 ether}(id, bytes("x"), address(sink), sink.onResult.selector);

        // Re-activating restores it.
        vm.prank(agentOwner);
        registry.update(id, 0.01 ether, "ipfs://meta", true);
        assertTrue(registry.getAgent(id).active);
    }

    /* ------------------------- transferAgent ------------------------ */

    function test_transferAgent_movesOwnershipAndIndex() public {
        uint256 id = _registerExternal(0.01 ether);

        vm.prank(agentOwner);
        registry.transferAgent(id, bob);

        assertEq(registry.getAgent(id).owner, bob);

        uint256[] memory bobsAgents = registry.agentsByOwner(bob);
        bool found;
        for (uint256 i; i < bobsAgents.length; ++i) {
            if (bobsAgents[i] == id) found = true;
        }
        assertTrue(found);
    }

    function test_transferAgent_revertsForNonOwner() public {
        uint256 id = _registerExternal(0.01 ether);
        vm.prank(bob);
        vm.expectRevert(AgentRegistry.NotAgentOwner.selector);
        registry.transferAgent(id, bob);
    }

    function test_transferAgent_revertsOnZeroRecipient() public {
        uint256 id = _registerExternal(0.01 ether);
        vm.prank(agentOwner);
        vm.expectRevert(bytes("zero recipient"));
        registry.transferAgent(id, address(0));
    }

    function test_transferAgent_revertsOnUnknownAgent() public {
        vm.prank(agentOwner);
        vm.expectRevert(AgentRegistry.UnknownAgent.selector);
        registry.transferAgent(424242, bob);
    }

    /* --------------------------- update guards ---------------------- */

    function test_update_revertsForNonOwner() public {
        uint256 id = _registerExternal(0.01 ether);
        vm.prank(bob);
        vm.expectRevert(AgentRegistry.NotAgentOwner.selector);
        registry.update(id, 0.02 ether, "ipfs://meta", true);
    }

    function test_register_revertsOnEmptyMetadataAndTag() public {
        vm.startPrank(agentOwner);
        vm.expectRevert(AgentRegistry.EmptyMetadata.selector);
        registry.register(AgentRegistry.AgentType.EXTERNAL, 0, 0, "", "tag");

        vm.expectRevert(AgentRegistry.EmptyTag.selector);
        registry.register(AgentRegistry.AgentType.EXTERNAL, 0, 0, "ipfs://meta", "");
        vm.stopPrank();
    }

    /* ------------------------------ pausing ------------------------- */

    function test_pause_blocksRegisterAndInvoke() public {
        uint256 id = _registerExternal(0.01 ether);

        vm.prank(admin);
        registry.pause();
        vm.prank(agentOwner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.register(AgentRegistry.AgentType.EXTERNAL, 0, 0, "ipfs://m", "t");

        vm.prank(admin);
        hub.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        hub.invoke{value: 0.01 ether}(id, bytes("x"), address(sink), sink.onResult.selector);
    }

    function test_pause_onlyOwner() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bob)
        );
        hub.pause();
    }

    /* --------------------------- protocol fee ----------------------- */

    function test_protocolFee_accruesToTreasury() public {
        vm.prank(admin);
        hub.setProtocolFee(500); // 5%

        uint256 id = _registerExternal(0.02 ether);
        uint256 protocolFee = (0.02 ether * 500) / 10_000; // 0.001 ether

        hub.invoke{value: 0.02 ether + protocolFee}(
            id, bytes("x"), address(sink), sink.onResult.selector
        );

        assertEq(hub.withdrawable(treasury), protocolFee);
    }

    function test_setProtocolFee_revertsAboveCap() public {
        vm.prank(admin);
        vm.expectRevert(MosaicHub.FeeTooHigh.selector);
        hub.setProtocolFee(1001); // > 10%
    }

    /* ----------------------- fulfill double-spend ------------------- */

    function test_fulfill_revertsIfAlreadySettled() public {
        uint256 id = _registerExternal(0.02 ether);
        uint256 invId =
            hub.invoke{value: 0.02 ether}(id, bytes("x"), address(sink), sink.onResult.selector);

        bytes memory result = abi.encode("done");
        bytes32 digest = keccak256(abi.encode(address(hub), invId, result));
        bytes32 ethDigest =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentOwnerPk, ethDigest);
        bytes memory sig = abi.encodePacked(r, s, v);

        hub.fulfillIntent(invId, result, sig);

        // Second fulfillment of the same invocation must revert.
        vm.expectRevert(MosaicHub.AlreadySettled.selector);
        hub.fulfillIntent(invId, result, sig);
    }

    function test_refundExpired_revertsForUnauthorizedCaller() public {
        uint256 id = _registerExternal(0.02 ether);
        uint256 invId =
            hub.invoke{value: 0.02 ether}(id, bytes("x"), address(sink), sink.onResult.selector);

        vm.warp(block.timestamp + 1 hours + 1);
        // bob is neither caller, agent owner, nor hub owner.
        vm.prank(bob);
        vm.expectRevert(bytes("not authorized"));
        hub.refundExpired(invId);
    }

    /* ------------------------ reputation guards --------------------- */

    function test_reputation_recordOnlyHub() public {
        vm.expectRevert(ReputationLedger.NotHub.selector);
        reputation.record(1, ReputationLedger.Outcome.Success, 0);
    }

    function test_reputation_setHubRejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(ReputationLedger.InvalidHub.selector);
        reputation.setHub(address(0));
    }

    function test_reputation_emptyStatsReturnZero() public {
        assertEq(reputation.successRateBps(123), 0);
        assertEq(reputation.averageLatencyMs(123), 0);
    }

    // Allow this test contract to receive overpay refunds + withdrawals.
    receive() external payable {}
}
