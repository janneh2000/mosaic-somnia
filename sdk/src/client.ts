import {
    createPublicClient,
    createWalletClient,
    decodeFunctionData,
    encodeAbiParameters,
    encodePacked,
    hashMessage,
    http,
    keccak256,
    parseAbiItem,
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

    /**
     * Wait for an invocation to settle, then reconstruct the agent's returned
     * bytes. The result isn't stored on-chain — it's an argument to the runner's
     * `fulfillIntent` call — so we locate the InvocationFulfilled log for this
     * id and decode the result out of that transaction's calldata. Used by the
     * Composer to read a sub-agent's output without a dedicated callback sink.
     */
    async awaitFulfillment(
        invocationId: bigint,
        opts: { pollMs?: number; tries?: number } = {}
    ): Promise<{ status: InvocationStatus; result?: Hex; fulfillTx?: Hex }> {
        const pollMs = opts.pollMs ?? 2_000;
        const tries = opts.tries ?? 45;
        const fulfilledEvent = parseAbiItem(
            "event InvocationFulfilled(uint256 indexed invocationId, uint256 indexed agentId, uint8 status, uint128 latencyMs)"
        );
        for (let i = 0; i < tries; i++) {
            // Somnia's public RPC is rate-limited and intermittently drops reads.
            // A single transient failure must not abort the whole wait — retry the
            // status read a few times, and if it still fails just poll again.
            let inv: InvocationRecord;
            try {
                inv = await withRetry(() => this.getInvocation(invocationId), {
                    tries: 3,
                    delayMs: 600
                });
            } catch {
                await new Promise((r) => setTimeout(r, pollMs));
                continue;
            }
            if (inv.status !== InvocationStatus.Pending) {
                if (inv.status !== InvocationStatus.Fulfilled) return { status: inv.status };
                try {
                    // Bounded window (Somnia caps eth_getLogs at 1000 blocks); the
                    // fulfillment landed within the last poll cycle.
                    const head = await withRetry(() => this.publicClient.getBlockNumber());
                    const fromBlock = head > 900n ? head - 900n : 0n;
                    const logs = await withRetry(() =>
                        this.publicClient.getLogs({
                            address: this.addresses.mosaicHub,
                            event: fulfilledEvent,
                            args: { invocationId },
                            fromBlock,
                            toBlock: head
                        })
                    );
                    if (logs.length === 0) return { status: inv.status };
                    const fulfillTx = logs[0]!.transactionHash as Hex;
                    const tx = await withRetry(() =>
                        this.publicClient.getTransaction({ hash: fulfillTx })
                    );
                    const { functionName, args } = decodeFunctionData({
                        abi: mosaicHubAbi,
                        data: tx.input
                    });
                    if (functionName === "fulfillIntent") {
                        return {
                            status: inv.status,
                            result: (args as readonly unknown[])[1] as Hex,
                            fulfillTx
                        };
                    }
                    return { status: inv.status, fulfillTx };
                } catch {
                    // Settled, but we couldn't fetch/decode the result bytes.
                    return { status: inv.status };
                }
            }
            await new Promise((r) => setTimeout(r, pollMs));
        }
        return { status: InvocationStatus.Pending };
    }

    /**
     * Invoke an EXTERNAL agent and block until it settles, returning the
     * decoded result bytes plus both transaction hashes for verifiability.
     */
    async invokeAndAwait(
        opts: {
            agentId: bigint;
            payload: Hex;
            value: bigint;
            callbackContract?: Address;
            callbackSelector?: Hex;
        },
        awaitOpts: { pollMs?: number; tries?: number } = {}
    ): Promise<{
        invocationId: bigint;
        invokeTx: Hex;
        status: InvocationStatus;
        result?: Hex;
        fulfillTx?: Hex;
    }> {
        this._requireSigner();
        // Deliver to our own EOA by default (a no-op low-level call); we read the
        // result from the fulfillment calldata, so no callback contract is needed.
        const callbackContract = opts.callbackContract ?? this.account!.address;
        const callbackSelector = opts.callbackSelector ?? ("0x00000000" as Hex);
        const invokeTx = await this.walletClient!.writeContract({
            account: this.account!,
            chain: this.publicClient.chain,
            address: this.addresses.mosaicHub,
            abi: mosaicHubAbi,
            functionName: "invoke",
            args: [opts.agentId, opts.payload, callbackContract, callbackSelector],
            value: opts.value
        });
        const receipt = await withRetry(() =>
            this.publicClient.waitForTransactionReceipt({ hash: invokeTx })
        );
        const intentLogs = parseEventLogs({
            abi: mosaicHubAbi,
            logs: receipt.logs,
            eventName: "IntentCreated"
        });
        if (intentLogs.length === 0) {
            throw new Error("invokeAndAwait: no IntentCreated event (EXTERNAL agents only)");
        }
        const invocationId = (intentLogs[0]!.args as { invocationId: bigint }).invocationId;
        const settled = await this.awaitFulfillment(invocationId, awaitOpts);
        return { invocationId, invokeTx, ...settled };
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

/**
 * Retry an async call with linear backoff. Built for Somnia's public RPC, which
 * is rate-limited and occasionally drops reads under load. Keep the retried fn
 * idempotent (reads only).
 */
export async function withRetry<T>(
    fn: () => Promise<T>,
    opts: { tries?: number; delayMs?: number } = {}
): Promise<T> {
    const tries = opts.tries ?? 4;
    const delayMs = opts.delayMs ?? 800;
    let lastErr: unknown;
    for (let i = 0; i < tries; i++) {
        try {
            return await fn();
        } catch (e) {
            lastErr = e;
            if (i < tries - 1) {
                await new Promise((r) => setTimeout(r, delayMs * (i + 1)));
            }
        }
    }
    throw lastErr;
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
