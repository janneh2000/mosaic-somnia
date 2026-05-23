#!/usr/bin/env bash
# Applies two fixes:
#   1. patches sdk/src/runner.ts to chunk eth_getLogs at 500 blocks per call
#      (fixes the "block range exceeds 1000" loop on Somnia's public RPC)
#   2. writes agents/whoOwnsGuardian.ts so we can verify whether the runner's
#      wallet matches the registered Guardian agent owner.
set -euo pipefail

REPO="${REPO:-$HOME/Desktop/mosaic-somnia/mosaic}"

if [ ! -d "$REPO/sdk/src" ] || [ ! -d "$REPO/agents/src" ]; then
    echo "✗ couldn't find $REPO/sdk and $REPO/agents"
    echo "  Set REPO=/path/to/mosaic and re-run."
    exit 1
fi

############################################
# 1. patched sdk/src/runner.ts
############################################
cat > "$REPO/sdk/src/runner.ts" <<'TS'
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

const INTENT_CREATED_EVENT = parseAbiItem(
    "event IntentCreated(uint256 indexed invocationId, uint256 indexed agentId, address indexed caller, bytes payload, uint256 fee, uint256 nonce)"
);

export interface RunnerOptions {
    client: MosaicClient;
    agentId: bigint;
    fromBlock?: bigint | "latest";
    pollIntervalMs?: number;
    handle: (payload: Hex, ctx: IntentContext) => Promise<Hex>;
}

export interface IntentContext {
    invocationId: bigint;
    caller: Address;
    fee: bigint;
}

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

        // Somnia's public RPC caps eth_getLogs at 1000 blocks per call. Chunk
        // well below that so the runner can also catch up after long idle
        // periods without spamming the node.
        const MAX_RANGE = 500n;

        while (!this.stopped) {
            try {
                const head = await client.publicClient.getBlockNumber();
                if (head < cursor) {
                    await sleep(interval);
                    continue;
                }
                let from = cursor;
                while (from <= head && !this.stopped) {
                    const to = from + MAX_RANGE - 1n > head ? head : from + MAX_RANGE - 1n;
                    const logs = await client.publicClient.getLogs({
                        address: client.addresses.mosaicHub,
                        event: INTENT_CREATED_EVENT,
                        args: { agentId },
                        fromBlock: from,
                        toBlock: to
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
                            const result = await handle(payload, {
                                invocationId,
                                caller,
                                fee
                            });
                            const sig = await this._sign(invocationId, result);
                            const tx = await client.fulfillIntent(
                                invocationId,
                                result,
                                sig
                            );
                            console.log(`[runner] fulfilled tx=${tx}`);
                        } catch (err) {
                            console.error(
                                `[runner] handler error for invocation=${invocationId}:`,
                                err
                            );
                        }
                    }
                    from = to + 1n;
                    cursor = from;
                }
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

export function decodeMethodCall(payload: Hex): { method: string; args: Hex } {
    const [method, args] = decodeAbiParameters(
        [{ type: "string" }, { type: "bytes" }],
        payload
    ) as [string, Hex];
    return { method, args };
}

export function encodeMethodCall(method: string, args: Hex): Hex {
    return encodeAbiParameters(
        [{ type: "string" }, { type: "bytes" }],
        [method, args]
    );
}
TS

############################################
# 2. agents/whoOwnsGuardian.ts — wrapped in async main() so it works with CJS
############################################
cat > "$REPO/agents/src/whoOwnsGuardian.ts" <<'TS'
import { createPublicClient, http, type Address } from "viem";
import { agentRegistryAbi, somniaTestnet } from "@mosaic/sdk";

async function main() {
    const client = createPublicClient({
        chain: somniaTestnet,
        transport: http(process.env.SOMNIA_RPC_URL!)
    });

    const agentId = BigInt(process.env.GUARDIAN_AGENT_ID ?? "1");
    const agent = (await client.readContract({
        address: process.env.AGENT_REGISTRY_ADDRESS as Address,
        abi: agentRegistryAbi,
        functionName: "getAgent",
        args: [agentId]
    })) as { owner: Address; capabilityTag: string; active: boolean };

    console.log("\n--- Guardian ownership check ---");
    console.log("agent id queried:        ", agentId.toString());
    console.log("on-chain owner:          ", agent.owner);
    console.log("on-chain capability tag: ", agent.capabilityTag);
    console.log("on-chain active:         ", agent.active);
    console.log();
    console.log("Compare 'on-chain owner' above against the wallet whose key");
    console.log("you put into AGENT_PRIVATE_KEY in agents/.env. They MUST match");
    console.log("for fulfillIntent to succeed.");
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
TS

echo "✓ patched $REPO/sdk/src/runner.ts (eth_getLogs now chunked at 500 blocks)"
echo "✓ wrote   $REPO/agents/src/whoOwnsGuardian.ts"
echo
echo "Next steps:"
echo "  1. Find out who actually owns Guardian:"
echo "       cd $REPO/agents"
echo "       npx tsx --env-file=.env src/whoOwnsGuardian.ts"
echo
echo "  2. If the on-chain owner does NOT match the runner wallet, swap"
echo "     AGENT_PRIVATE_KEY in agents/.env for the matching wallet's key,"
echo "     then restart the three runners."
echo
echo "  3. Either way, the runner fix takes effect on next restart. Stop"
echo "     each runner (Ctrl-C), then in each terminal:"
echo "       cd $REPO/agents"
echo "       set -a; source .env; set +a"
echo "       npm run guardian       # terminal 1"
echo "       npm run summarizer     # terminal 2"
echo "       npm run composer       # terminal 3"
