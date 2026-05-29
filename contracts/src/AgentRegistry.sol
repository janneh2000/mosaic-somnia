// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title  AgentRegistry
/// @notice On-chain directory of agents available in the Mosaic marketplace.
/// @dev    Two agent types are supported:
///           - NATIVE   : runs on Somnia's validator network via SomniaAgents
///           - EXTERNAL : runs off-chain; runners listen for IntentCreated
///                        events from MosaicHub and post signed fulfillments.
contract AgentRegistry is Ownable2Step, Pausable {
    /* ----------------------------- types ----------------------------- */

    enum AgentType {
        NATIVE,
        EXTERNAL
    }

    struct Agent {
        address owner; // who controls the agent + receives fees
        AgentType agentType;
        uint256 nativeAgentId; // only meaningful for NATIVE
        uint256 pricePerInvocation; // in wei (STT)
        string metadataURI; // ipfs:// or data: URI for capability schema
        string capabilityTag; // single-word tag for indexing (e.g. "security")
        bool active;
        uint64 registeredAt;
    }

    /* ----------------------------- state ----------------------------- */

    /// @dev agentId 0 is reserved as "unset".
    uint256 public nextAgentId = 1;

    mapping(uint256 => Agent) private _agents;
    mapping(bytes32 => uint256[]) private _byTag;
    mapping(address => uint256[]) private _byOwner;

    /* ---------------------------- events ----------------------------- */

    event AgentRegistered(
        uint256 indexed agentId,
        address indexed owner,
        AgentType agentType,
        uint256 nativeAgentId,
        uint256 pricePerInvocation,
        string capabilityTag,
        string metadataURI
    );
    event AgentUpdated(
        uint256 indexed agentId, uint256 pricePerInvocation, string metadataURI, bool active
    );
    event AgentTransferred(uint256 indexed agentId, address indexed from, address indexed to);

    /* ---------------------------- errors ----------------------------- */

    error NotAgentOwner();
    error UnknownAgent();
    error EmptyTag();
    error EmptyMetadata();
    error NativeAgentIdRequired();

    /* --------------------------- modifiers --------------------------- */

    modifier onlyAgentOwner(uint256 agentId) {
        if (_agents[agentId].owner == address(0)) revert UnknownAgent();
        if (_agents[agentId].owner != msg.sender) revert NotAgentOwner();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    /* ------------------------- registration -------------------------- */

    /// @notice Register a new agent in the marketplace.
    /// @param  agentType            NATIVE (Somnia validator-run) or EXTERNAL (off-chain).
    /// @param  nativeAgentId        Somnia native agent ID; required iff type == NATIVE.
    /// @param  pricePerInvocation   Fee (wei) the caller must pay per invocation.
    /// @param  metadataURI          Capability schema URI (MCP-compatible JSON).
    /// @param  capabilityTag        Single short tag for discovery (e.g. "security", "oracle").
    function register(
        AgentType agentType,
        uint256 nativeAgentId,
        uint256 pricePerInvocation,
        string calldata metadataURI,
        string calldata capabilityTag
    ) external whenNotPaused returns (uint256 agentId) {
        if (bytes(metadataURI).length == 0) revert EmptyMetadata();
        if (bytes(capabilityTag).length == 0) revert EmptyTag();
        if (agentType == AgentType.NATIVE && nativeAgentId == 0) revert NativeAgentIdRequired();

        agentId = nextAgentId++;
        _agents[agentId] = Agent({
            owner: msg.sender,
            agentType: agentType,
            nativeAgentId: nativeAgentId,
            pricePerInvocation: pricePerInvocation,
            metadataURI: metadataURI,
            capabilityTag: capabilityTag,
            active: true,
            registeredAt: uint64(block.timestamp)
        });

        _byTag[_tagKey(capabilityTag)].push(agentId);
        _byOwner[msg.sender].push(agentId);

        emit AgentRegistered(
            agentId,
            msg.sender,
            agentType,
            nativeAgentId,
            pricePerInvocation,
            capabilityTag,
            metadataURI
        );
    }

    /// @notice Update mutable fields of an agent.
    function update(
        uint256 agentId,
        uint256 pricePerInvocation,
        string calldata metadataURI,
        bool active
    ) external onlyAgentOwner(agentId) whenNotPaused {
        if (bytes(metadataURI).length == 0) revert EmptyMetadata();
        Agent storage a = _agents[agentId];
        a.pricePerInvocation = pricePerInvocation;
        a.metadataURI = metadataURI;
        a.active = active;
        emit AgentUpdated(agentId, pricePerInvocation, metadataURI, active);
    }

    /// @notice Transfer ownership of an agent record.
    function transferAgent(uint256 agentId, address to)
        external
        onlyAgentOwner(agentId)
        whenNotPaused
    {
        require(to != address(0), "zero recipient");
        address prev = _agents[agentId].owner;
        _agents[agentId].owner = to;
        _byOwner[to].push(agentId);
        emit AgentTransferred(agentId, prev, to);
    }

    /* --------------------------- queries ----------------------------- */

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        if (_agents[agentId].owner == address(0)) revert UnknownAgent();
        return _agents[agentId];
    }

    function exists(uint256 agentId) external view returns (bool) {
        return _agents[agentId].owner != address(0);
    }

    function agentsByTag(string calldata tag) external view returns (uint256[] memory) {
        return _byTag[_tagKey(tag)];
    }

    function agentsByOwner(address owner) external view returns (uint256[] memory) {
        return _byOwner[owner];
    }

    /* ---------------------------- admin ------------------------------ */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* --------------------------- internal ---------------------------- */

    function _tagKey(string memory tag) internal pure returns (bytes32) {
        return keccak256(bytes(tag));
    }
}
