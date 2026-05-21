import type { Address, Hex } from "viem";

/** MCP-compatible capability schema. Stored at `metadataURI` for each agent. */
export interface AgentCapabilitySchema {
    /** Human-readable agent name. */
    name: string;
    /** Short category, e.g. "security", "oracle", "summarizer". Must match capabilityTag. */
    kind: string;
    /** Semver string for the agent's interface. */
    version: string;
    /** Free-form description. */
    description?: string;
    /** Method signatures the agent exposes (MCP-style). */
    methods: CapabilityMethod[];
    /** Optional URL where the off-chain runner is reachable for healthchecks. */
    runner?: string;
}

export interface CapabilityMethod {
    /** Method name, e.g. "scan", "fetchPrice", "summarize". */
    name: string;
    /** Args as ABI types (Solidity). */
    args: ParamSchema[];
    /** Return-value ABI type, encoded as a single bytes payload. */
    returns: ParamSchema[];
    /** Optional plain-English description. */
    description?: string;
}

export interface ParamSchema {
    name: string;
    /** Solidity ABI type, e.g. "address", "uint256", "bytes", "string". */
    type: string;
}

export enum AgentType {
    NATIVE = 0,
    EXTERNAL = 1
}

export enum InvocationStatus {
    Pending = 0,
    Fulfilled = 1,
    Failed = 2,
    TimedOut = 3,
    Refunded = 4
}

export interface AgentRecord {
    owner: Address;
    agentType: AgentType;
    nativeAgentId: bigint;
    pricePerInvocation: bigint;
    metadataURI: string;
    capabilityTag: string;
    active: boolean;
    registeredAt: bigint;
}

export interface InvocationRecord {
    agentId: bigint;
    caller: Address;
    callbackContract: Address;
    callbackSelector: Hex;
    feeEscrowed: bigint;
    createdAt: bigint;
    status: InvocationStatus;
    somniaRequestId: bigint;
}

export interface ReputationStats {
    totalInvocations: bigint;
    successCount: bigint;
    failureCount: bigint;
    timeoutCount: bigint;
    cumulativeLatencyMs: bigint;
    lastUpdatedAt: bigint;
}

export interface MosaicAddresses {
    agentRegistry: Address;
    mosaicHub: Address;
    reputationLedger: Address;
    guardianModule?: Address;
}
