import {
    createPublicClient,
    createWalletClient,
    encodeAbiParameters,
    encodePacked,
    hashMessage,
    http,
    keccak256,
    parseEventLogs,
    toBytes,
    type Account,
    type Address,
    type Hex,
    type PublicClient,
    type Transport,
    type WalletClient
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { agentRegistryAbi, guardianAbi, mosaicHubAbi, reputationLedgerAbi } from "./abi";
import { somniaTestnet } from "./chain";
import {
    AgentType,
    InvocationStatus,
    type AgentCapabilitySchema,
    type AgentRecord,
    type InvocationRecord,
    type MosaicAddresses,
    type ReputationStats
} from "./types";

export interface MosaicClientConfig {
    addresses: MosaicAddresses;
    rpcUrl?: string;
    chain?: typeof somniaTestnet;
    privateKey?: Hex;
}

/**
 * High-level Mosaic client. Thin facade over viem + the marketplace contracts.
 * Designed to be the only entrypoint other than direct contract calls.
 */
export class MosaicClient {
    readonly publicClient: PublicClient;
    readonly walletClient?: WalletClient;
    readonly account?: Account;
    readonly addresses: MosaicAddresses;

    constructor(cfg: MosaicClientConfig) {
        const chain = cfg.chain ?? somniaTestnet;
        const transport: Transport = http(cfg.rpcUrl ?? chain.rpcUrls.default.http[0]);
        this.publicClient = createPublicClient({ chain, transport });
        this.addresses = cfg.addresses;
        if (cfg.privateKey) {
            this.account = privateKeyToAccount(cfg.privateKey);
            this.walletClient = createWalletClient({ account: this.account, chain, transport });
        }
    }

    /* --------------------------- discovery --------------------------- */

    async getAgent(agentId: bigint): Promise<AgentRecord> {
        const raw = await this.publicClient.readContract({
            address: this.addresses.agentRegistry,
            abi: agentRegistryAbi,
            functionName: "getAgent",
            args: [agentId]
        });
        return {
            owner: raw.owner,
            agentType: raw.agentType as AgentType,
            nativeAgentId: raw.nativeAgentId,
            pricePerInvocation: raw.pricePerInvocation,
            metadataURI: raw.metadataURI,
            capabilityTag: raw.capabilityTag,
            active: raw.active,
            registeredAt: BigInt(raw.registeredAt)
        };
    }

    async listByTag(tag: string): Promise<bigint[]> {
        return (await this.publicClient.readContract({
            address: this.addresses.agentRegistry,
            abi: agentRegistryAbi,
            functionName: "agentsByTag",
            args: [tag]
        })) as bigint[];
    }

    async listAll(): Promise<{ id: bigint; record: AgentRecord }[]> {
        const next = (await this.publicClient.readContract({
            address: this.addresses.agentRegistry,
            abi: agentRegistryAbi,
            functionName: "nextAgentId"
        })) as bigint;
        const ids: bigint[] = [];
        for (let i = 1n; i < next; i++) ids.push(i);
        const records = await Promise.all(ids.map((id) => this.getAgent(id).catch(() => null)));
        const out: { id: bigint; record: AgentRecord }[] = [];
        ids.forEach((id, idx) => {
            const r = records[idx];
            if (r) out.push({ id, record: r });
        });
        return out;
    }

    async getReputation(agentId: bigint): Promise<ReputationStats> {
        const raw = await this.publicClient.readContract({
            address: this.addresses.reputationLedger,
            abi: reputationLedgerAbi,
            functionName: "getStats",
            args: [agentId]
        });
        return {
            totalInvocations: BigInt(raw.totalInvocations),
            successCount: BigInt(raw.successCount),
            failureCount: BigInt(raw.failureCount),
            timeoutCount: BigInt(raw.timeoutCount),
            cumulativeLatencyMs: BigInt(raw.cumulativeLatencyMs),
            lastUpdatedAt: BigInt(raw.lastUpdatedAt)
        };
    }

    /* ------------------------- registration -------------------------- */

    async register(opts: {
        agentType: AgentType;
        nativeAgentId?: bigint;
        pricePerInvocation: bigint;
        metadataURI: string;
        capabilityTag: string;
    }): Promise<bigint> {
        this._requireSigner();
        const hash = await this.walletClient!.writeContract({
            account: this.account!,
            chain: this.publicClient.chain,
            address: this.addresses.agentRegistry,
            abi: agentRegistryAbi,
            functionName: "register",
            args: [
                opts.agentType,
                opts.nativeAgentId ?? 0n,
                opts.pricePerInvocation,
                opts.metadataURI,
                opts.capabilityTag
            ]
        });
        const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
        const logs = parseEventLogs({
            abi: agentRegistryAbi,
            logs: receipt.logs,
            eventName: "AgentRegistered"
        });
        if (logs.length === 0) throw new Error("AgentRegistered log not found");
        return (logs[0]!.args as { agentId: bigint }).agentId;
    }

    /* --------------------------- invocation -------------------------- */

    async invoke(opts: {
        agentId: bigint;
        payload: Hex;
        callbackContract: Address;
        callbackSelector: Hex;
        value: bigint;
    }): Promise<bigint> {
        this._requireSigner();
        const hash = await this.walletClient!.writeContract({
            account: this.account!,
            chain: this.publicClient.chain,
            address: this.addresses.mosaicHub,
            abi: mosaicHubAbi,
            functionName: "invoke",
            args: [opts.agentId, opts.payload, opts.callbackContract, opts.callbackSelector],
            value: opts.value
        });
        const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
        // EXTERNAL invocation → IntentCreated event.
        const intentLogs = parseEventLogs({
            abi: mosaicHubAbi,
            logs: receipt.logs,
            eventName: "IntentCreated"
        });
        if (intentLogs.length > 0) {
            return (intentLogs[0]!.args as { invocationId: bigint }).invocationId;
        }
        // NATIVE invocation → NativeRequestForwarded event.
        const nativeLogs = parseEventLogs({
            abi: mosaicHubAbi,
            logs: receipt.logs,
            eventName: "NativeRequestForwarded"
        });
        if (nativeLogs.length > 0) {
            return (nativeLogs[0]!.args as { invocationId: bigint }).invocationId;
        }
        throw new Error("invoke succeeded but no Mosaic invocation event was emitted");
    }

    async getInvocation(id: bigint): Promise<InvocationRecord> {
        const raw = await this.publicClient.readContract({
            address: this.addresses.mosaicHub,
            abi: mosaicHubAbi,
            functionName: "invocations",
            args: [id]
        });
        const [
            agentId,
            caller,
            callbackContract,
            callbackSelector,
            feeEscrowed,
            createdAt,
            status,
            somniaRequestId
        ] = raw as unknown as [
            bigint,
            Address,
            Address,
            Hex,
            bigint,
            bigint,
            number,
            bigint
        ];
        return {
            agentId,
            caller,
            callbackContract,
            callbackSelector,
            feeEscrowed,
            createdAt,
            status: status as InvocationStatus,
            somniaRequestId
        };
    }

    /* ---------------------- runner fulfillment ---------------------- */

    /**
     * Build the EIP-191 signed-message digest the Hub expects when verifying
     * external-agent fulfillment.
     */
    static buildFulfillmentDigest(hub: Address, invocationId: bigint, result: Hex): Hex {
        const inner = keccak256(
            encodeAbiParameters(
                [
                    { type: "address" },
                    { type: "uint256" },
                    { type: "bytes" }
                ],
                [hub, invocationId, result]
            )
        );
        // EIP-191 personal-sign prefix (matches MessageHashUtils.toEthSignedMessageHash on-chain)
        return hashMessage({ raw: toBytes(inner) });
    }

    async fulfillIntent(invocationId: bigint, result: Hex, signature: Hex): Promise<Hex> {
        this._requireSigner();
        return await this.walletClient!.writeContract({
            account: this.account!,
            chain: this.publicClient.chain,
            address: this.addresses.mosaicHub,
            abi: mosaicHubAbi,
            functionName: "fulfillIntent",
            args: [invocationId, result, signature]
        });
    }

    /* ------------------------- pull payment ------------------------- */

    async withdrawable(addr: Address): Promise<bigint> {
        return (await this.publicClient.readContract({
            address: this.addresses.mosaicHub,
            abi: mosaicHubAbi,
            functionName: "withdrawable",
            args: [addr]
        })) as bigint;
    }

    async withdraw(): Promise<Hex> {
        this._requireSigner();
        return await this.walletClient!.writeContract({
            account: this.account!,
            chain: this.publicClient.chain,
            address: this.addresses.mosaicHub,
            abi: mosaicHubAbi,
            functionName: "withdraw"
        });
    }

    /* --------------------------- helpers ---------------------------- */

    _requireSigner() {
        if (!this.walletClient || !this.account) {
            throw new Error("MosaicClient: privateKey is required for write operations");
        }
    }
}

/** Build a `data:application/json,...` URI from a capability schema. */
export function encodeCapabilityAsDataUri(schema: AgentCapabilitySchema): string {
    const json = JSON.stringify(schema);
    return "data:application/json;base64," + Buffer.from(json, "utf8").toString("base64");
}

/** Decode a `data:application/json,...` URI back to a capability schema. */
export function decodeCapabilityFromDataUri(uri: string): AgentCapabilitySchema | null {
    const m = /^data:application\/json(;base64)?,(.*)$/.exec(uri);
    if (!m) return null;
    const isB64 = m[1] === ";base64";
    const raw = isB64 ? Buffer.from(m[2]!, "base64").toString("utf8") : decodeURIComponent(m[2]!);
    try {
        return JSON.parse(raw) as AgentCapabilitySchema;
    } catch {
        return null;
    }
}

// Re-export selected viem helpers callers will commonly want.
export { encodeAbiParameters, encodePacked, keccak256 };
