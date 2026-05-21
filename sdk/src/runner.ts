import {
    decodeAbiParameters,
    encodeAbiParameters,
    keccak256,
    parseAbiItem,
    parseEventLogs,
    toBytes,
    type Address,
    type Hex
} from "viem";

import { mosaicHubAbi } from "./abi";
import { MosaicClient } from "./client";

// Typed event reference so viem can narrow the `args` filter type.
const INTENT_CREATED_EVENT = parseAbiItem(
    "event IntentCreated(uint256 indexed invocationId, uint256 indexed agentId, address indexed caller, bytes payload, uint256 fee, uint256 nonce)"
);

export interface RunnerOptions {
    /** Mosaic client (must be initialized with the agent owner's private key). */
    client: MosaicClient;
    /** Mosaic agent id this runner is fulfilling. */
    agentId: bigint;
    /** Block number to start scanning from. Pass `latest` for tail-only. */
    fromBlock?: bigint | "latest";
    /** Polling interval in milliseconds. */
    pollIntervalMs?: number;
    /** Handler that takes the agent payload bytes and returns the result bytes. */
    handle: (payload: Hex, ctx: IntentContext) => Promise<Hex>;
}

export interface IntentContext {
    invocationId: bigint;
    caller: Address;
    fee: bigint;
}

/**
 * Long-polling external-agent runner. Listens for IntentCreated events for a
 * specific agent id, calls the handler, posts a signed fulfillment back to
 * MosaicHub.
 *
 * Designed for SIMPLE single-machine setups. Production deployments will want
 * a watcher with retry queues and a key vault — but the protocol is permissive
 * about that: any process holding the agent owner's signing key can fulfill.
 */
export class AgentRunner {
    private stopped = false;

    constructor(private opts: RunnerOptions) {}

    async start(): Promise<void> {
        const { client, agentId, handle } = this.opts;
        const interval = this.opts.pollIntervalMs ?? 3_000;
        let cursor: bigint;
        if (this.opts.fromBlock === undefined || this.opts.fromBlock === "latest") {
            cursor = await client.publicClient.getBlockNumber();
        } else {
            cursor = this.opts.fromBlock;
        }
        const account = client.account!;
        if (!account) throw new Error("AgentRunner requires a signer (privateKey)");

        console.log(
            `[runner] starting agent=${agentId} owner=${account.address} fromBlock=${cursor}`
        );

        while (!this.stopped) {
            try {
                const head = await client.publicClient.getBlockNumber();
                if (head < cursor) {
                    await sleep(interval);
                    continue;
                }
                const logs = await client.publicClient.getLogs({
                    address: client.addresses.mosaicHub,
                    event: INTENT_CREATED_EVENT,
                    args: { agentId },
                    fromBlock: cursor,
                    toBlock: head
                });
                const parsed = parseEventLogs({
                    abi: mosaicHubAbi,
                    logs,
                    eventName: "IntentCreated"
                });
                for (const entry of parsed) {
                    const { invocationId, caller, payload, fee } = entry.args as {
                        invocationId: bigint;
                        caller: Address;
                        payload: Hex;
                        fee: bigint;
                    };
                    console.log(
                        `[runner] fulfilling invocation=${invocationId} caller=${caller}`
                    );
                    try {
                        const result = await handle(payload, { invocationId, caller, fee });
                        const sig = await this._sign(invocationId, result);
                        const tx = await client.fulfillIntent(invocationId, result, sig);
                        console.log(`[runner] fulfilled tx=${tx}`);
                    } catch (err) {
                        console.error(
                            `[runner] handler error for invocation=${invocationId}:`,
                            err
                        );
                    }
                }
                cursor = head + 1n;
            } catch (err) {
                console.error("[runner] poll error:", err);
            }
            await sleep(interval);
        }
    }

    stop() {
        this.stopped = true;
    }

    private async _sign(invocationId: bigint, result: Hex): Promise<Hex> {
        // MosaicHub expects: ecrecover over hashed(
        //   "\x19Ethereum Signed Message:\n32" || keccak256(abi.encode(hub, id, result))
        // ).
        // viem's account.signMessage({message: {raw}}) applies the EIP-191
        // prefix to the inner hash, which is exactly what the contract does.
        const inner = innerFulfillmentHash(
            this.opts.client.addresses.mosaicHub,
            invocationId,
            result
        );
        const acc = this.opts.client.account!;
        if (!acc.signMessage) throw new Error("signer cannot sign messages");
        return await acc.signMessage({ message: { raw: toBytes(inner) } });
    }
}

export function innerFulfillmentHash(
    hub: Address,
    invocationId: bigint,
    result: Hex
): Hex {
    return keccak256(
        encodeAbiParameters(
            [{ type: "address" }, { type: "uint256" }, { type: "bytes" }],
            [hub, invocationId, result]
        )
    );
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Decode an MCP-style payload encoded as abi.encode(methodName, argsBytes). */
export function decodeMethodCall(payload: Hex): { method: string; args: Hex } {
    const [method, args] = decodeAbiParameters(
        [{ type: "string" }, { type: "bytes" }],
        payload
    ) as [string, Hex];
    return { method, args };
}

/** Encode an MCP-style payload as abi.encode(methodName, argsBytes). */
export function encodeMethodCall(method: string, args: Hex): Hex {
    return encodeAbiParameters(
        [{ type: "string" }, { type: "bytes" }],
        [method, args]
    );
}
