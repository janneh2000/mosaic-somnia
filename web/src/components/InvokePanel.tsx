"use client";
import { useMemo, useState } from "react";
import {
    decodeAbiParameters,
    decodeFunctionData,
    encodeAbiParameters,
    formatEther,
    parseAbiItem,
    parseEventLogs,
    type Address,
    type Hex
} from "viem";
import { useAccount, useWriteContract } from "wagmi";
import {
    AgentType,
    InvocationStatus,
    mosaicHubAbi,
    somniaTestnet,
    withRetry,
    type AgentCapabilitySchema,
    type AgentRecord,
    type CapabilityMethod
} from "@mosaic/sdk";
import { config } from "@/lib/config";
import { getReadClient } from "@/lib/client";
import { ensureSomniaChain } from "@/lib/ensureChain";

const EXPLORER = somniaTestnet.blockExplorers.default.url;
// A no-op callback: we deliver to the caller's own EOA (a low-level call to an
// address with no code simply succeeds), and reconstruct the agent's output by
// decoding the runner's fulfillIntent calldata. Keeps invocation fully generic
// — no per-agent callback contract required.
const NOOP_SELECTOR = "0x00000000" as Hex;

type InvokeState =
    | { phase: "idle" }
    | { phase: "submitting" }
    | { phase: "pending"; invocationId: bigint; txHash: Hex }
    | {
          phase: "done";
          invocationId: bigint;
          txHash: Hex;
          status: InvocationStatus;
          fulfillTx?: Hex;
          decoded?: string;
          rawResult?: Hex;
          latencyMs?: number;
      }
    | { phase: "error"; message: string };

function coerceArg(type: string, value: string): unknown {
    if (type === "bool") return value === "true" || value === "1";
    if (type.startsWith("uint") || type.startsWith("int")) return BigInt(value || "0");
    // address, string, bytes*, etc. pass through as-is.
    return value;
}

/** Render the agent's returned bytes using its declared return schema. */
function decodeResult(method: CapabilityMethod | undefined, result: Hex): string | undefined {
    if (!result || result === "0x") return undefined;
    if (method && method.returns.length > 0) {
        try {
            const decoded = decodeAbiParameters(
                method.returns.map((r) => ({ type: r.type })),
                result
            );
            if (decoded.length === 1) return formatValue(decoded[0]);
            return method.returns
                .map((r, i) => `${r.name}: ${formatValue(decoded[i])}`)
                .join("\n");
        } catch {
            /* fall through to raw */
        }
    }
    return undefined;
}

function formatValue(v: unknown): string {
    if (typeof v === "bigint") return v.toString();
    if (typeof v === "string") return v;
    try {
        return JSON.stringify(v, (_k, x) => (typeof x === "bigint" ? x.toString() : x), 2);
    } catch {
        return String(v);
    }
}

export function InvokePanel({
    agentId,
    record,
    schema
}: {
    agentId: bigint;
    record: AgentRecord;
    schema: AgentCapabilitySchema | null;
}) {
    const { isConnected, address } = useAccount();
    const { writeContractAsync } = useWriteContract();
    const [state, setState] = useState<InvokeState>({ phase: "idle" });

    // Drive the form from the first capability method, when present.
    const method = schema?.methods?.[0];
    const [args, setArgs] = useState<string[]>(() => (method ? method.args.map(() => "") : []));
    const [rawPayload, setRawPayload] = useState("0x");

    const isExternal = record.agentType === AgentType.EXTERNAL;
    const busy = state.phase === "submitting" || state.phase === "pending";

    const payloadPreview = useMemo(() => {
        if (!method) return rawPayload;
        try {
            return encodeAbiParameters(
                method.args.map((a) => ({ type: a.type })),
                method.args.map((a, i) => coerceArg(a.type, args[i] ?? ""))
            );
        } catch {
            return null;
        }
    }, [method, args, rawPayload]);

    async function buildPayload(): Promise<Hex> {
        if (method) {
            return encodeAbiParameters(
                method.args.map((a) => ({ type: a.type })),
                method.args.map((a, i) => coerceArg(a.type, args[i] ?? ""))
            );
        }
        if (!/^0x[0-9a-fA-F]*$/.test(rawPayload)) throw new Error("payload must be 0x-hex");
        return rawPayload as Hex;
    }

    async function fetchResult(invocationId: bigint, fromBlock: bigint) {
        const client = getReadClient();
        // Somnia caps eth_getLogs range; keep the window small (fulfillment lands
        // within seconds of the invoke). Retry — the public RPC is rate-limited.
        const logs = await withRetry(() =>
            client.publicClient.getLogs({
                address: config.addresses.mosaicHub,
                event: parseAbiItem(
                    "event InvocationFulfilled(uint256 indexed invocationId, uint256 indexed agentId, uint8 status, uint128 latencyMs)"
                ),
                args: { invocationId },
                fromBlock,
                toBlock: fromBlock + 900n
            })
        );
        if (logs.length === 0) return { fulfillTx: undefined, result: undefined };
        const fulfillTx = logs[0]!.transactionHash as Hex;
        const tx = await withRetry(() =>
            client.publicClient.getTransaction({ hash: fulfillTx })
        );
        try {
            const { functionName, args: callArgs } = decodeFunctionData({
                abi: mosaicHubAbi,
                data: tx.input
            });
            if (functionName === "fulfillIntent") {
                return { fulfillTx, result: (callArgs as readonly unknown[])[1] as Hex };
            }
        } catch {
            /* refundExpired / other settlement path — no result bytes */
        }
        return { fulfillTx, result: undefined };
    }

    async function onInvoke() {
        setState({ phase: "submitting" });
        try {
            const active = await ensureSomniaChain();
            if (active !== somniaTestnet.id) {
                throw new Error(
                    `Wallet on chain ${active}. Switch to Somnia Testnet and retry.`
                );
            }
            const payload = await buildPayload();
            const client = getReadClient();

            const txHash = await writeContractAsync({
                address: config.addresses.mosaicHub,
                abi: mosaicHubAbi,
                functionName: "invoke",
                args: [agentId, payload, address as Address, NOOP_SELECTOR],
                value: record.pricePerInvocation
            });

            const receipt = await withRetry(
                () => client.publicClient.waitForTransactionReceipt({ hash: txHash }),
                { tries: 5, delayMs: 1_500 }
            );
            const intentLogs = parseEventLogs({
                abi: mosaicHubAbi,
                logs: receipt.logs,
                eventName: "IntentCreated"
            });
            if (intentLogs.length === 0) {
                throw new Error("invoke landed but no IntentCreated event found");
            }
            const invocationId = (intentLogs[0]!.args as { invocationId: bigint }).invocationId;
            const fromBlock = receipt.blockNumber;
            setState({ phase: "pending", invocationId, txHash });

            // Poll the on-chain invocation status until it settles. A transient
            // RPC failure on any single poll must not abort the wait. Meta-agents
            // like the Composer chain several sub-invocations, so allow up to ~4
            // minutes before giving up.
            for (let i = 0; i < 120; i++) {
                await new Promise((r) => setTimeout(r, 2_000));
                let inv;
                try {
                    inv = await withRetry(() => client.getInvocation(invocationId), {
                        tries: 3,
                        delayMs: 600
                    });
                } catch {
                    continue;
                }
                if (inv.status !== InvocationStatus.Pending) {
                    const latencyMs = Number(
                        (BigInt(Math.floor(Date.now() / 1000)) - inv.createdAt) * 1000n
                    );
                    let fulfillTx: Hex | undefined;
                    let rawResult: Hex | undefined;
                    let decoded: string | undefined;
                    if (inv.status === InvocationStatus.Fulfilled) {
                        // Result reconstruction (getLogs + getTransaction) is a
                        // best-effort bonus. The invocation already settled, so a
                        // flaky public RPC here must NOT turn a success into an
                        // error — we still show "fulfilled" + the invoke tx link.
                        try {
                            const r = await fetchResult(invocationId, fromBlock);
                            fulfillTx = r.fulfillTx;
                            rawResult = r.result;
                            decoded = decodeResult(method, r.result ?? "0x");
                        } catch {
                            /* keep success state; result just won't be shown */
                        }
                    }
                    setState({
                        phase: "done",
                        invocationId,
                        txHash,
                        status: inv.status,
                        fulfillTx,
                        rawResult,
                        decoded,
                        latencyMs
                    });
                    return;
                }
            }
            throw new Error(
                "still pending after ~4 min — the agent's runner may be offline or the public RPC is lagging. Your fee is safe and reclaimable via refundExpired after 1 hour."
            );
        } catch (err) {
            const msg =
                (err as { shortMessage?: string; message?: string })?.shortMessage ??
                (err as Error)?.message ??
                String(err);
            setState({ phase: "error", message: msg });
        }
    }

    if (!isExternal) {
        return (
            <div className="border rounded-xl p-5 bg-panel mt-6">
                <div className="text-zinc-500 text-sm">invoke</div>
                <p className="text-sm text-zinc-300 mt-2">
                    This is a Somnia native agent — invocations are settled by validator
                    consensus and require a platform deposit. The generic invoke panel covers
                    external (off-chain runner) agents.
                </p>
            </div>
        );
    }

    return (
        <div className="border rounded-xl p-5 bg-panel mt-6">
            <div className="flex items-center justify-between">
                <div className="text-zinc-500 text-sm">
                    invoke {method ? `· ${method.name}` : ""}
                </div>
                <div className="text-sm text-zinc-400">
                    {formatEther(record.pricePerInvocation)} STT
                </div>
            </div>

            <div className="mt-3 space-y-3">
                {method ? (
                    method.args.map((arg, i) => (
                        <div key={arg.name}>
                            <label className="text-sm text-zinc-400">
                                {arg.name} <span className="text-zinc-600">({arg.type})</span>
                            </label>
                            <input
                                className="input mt-1"
                                placeholder={arg.type}
                                value={args[i] ?? ""}
                                onChange={(e) => {
                                    const next = [...args];
                                    next[i] = e.target.value;
                                    setArgs(next);
                                }}
                            />
                        </div>
                    ))
                ) : (
                    <div>
                        <label className="text-sm text-zinc-400">
                            payload <span className="text-zinc-600">(abi-encoded hex)</span>
                        </label>
                        <input
                            className="input mt-1"
                            placeholder="0x…"
                            value={rawPayload}
                            onChange={(e) => setRawPayload(e.target.value)}
                        />
                    </div>
                )}

                <button
                    className="btn"
                    disabled={busy || !isConnected}
                    onClick={onInvoke}
                >
                    {state.phase === "submitting"
                        ? "Confirm in wallet…"
                        : state.phase === "pending"
                          ? "Waiting for runner…"
                          : `Invoke (${formatEther(record.pricePerInvocation)} STT)`}
                </button>

                {!isConnected && (
                    <p className="text-sm text-zinc-500">connect your wallet to invoke.</p>
                )}
                {payloadPreview === null && method && (
                    <p className="text-sm text-rose-400">
                        can&apos;t encode args — check the types above.
                    </p>
                )}
            </div>

            {state.phase === "pending" && (
                <p className="mt-4 text-sm text-zinc-400">
                    intent #{state.invocationId.toString()} created ·{" "}
                    <a
                        className="text-emerald-400 underline"
                        href={`${EXPLORER}/tx/${state.txHash}`}
                        target="_blank"
                        rel="noreferrer"
                    >
                        invoke tx
                    </a>{" "}
                    · waiting for the off-chain runner to fulfill (meta-agents that
                    chain several agents can take a minute)…
                </p>
            )}

            {state.phase === "error" && (
                <p className="mt-4 text-sm text-rose-400">{state.message}</p>
            )}

            {state.phase === "done" && (
                <div className="mt-4">
                    <div className="flex items-center gap-3">
                        {state.status === InvocationStatus.Fulfilled ? (
                            <span className="badge">fulfilled</span>
                        ) : state.status === InvocationStatus.TimedOut ? (
                            <span className="badge warn">timed out</span>
                        ) : (
                            <span className="badge bad">failed</span>
                        )}
                        {typeof state.latencyMs === "number" && state.latencyMs >= 0 && (
                            <span className="text-sm text-zinc-500">
                                ~{(state.latencyMs / 1000).toFixed(0)}s
                            </span>
                        )}
                    </div>

                    {state.decoded !== undefined && (
                        <>
                            <div className="text-zinc-500 text-sm mt-4">result</div>
                            <pre className="pre mt-1">{state.decoded}</pre>
                        </>
                    )}
                    {state.decoded === undefined &&
                        state.status === InvocationStatus.Fulfilled &&
                        state.rawResult && (
                            <>
                                <div className="text-zinc-500 text-sm mt-4">result (raw)</div>
                                <pre className="pre mt-1">{state.rawResult}</pre>
                            </>
                        )}
                    {state.decoded === undefined &&
                        state.rawResult === undefined &&
                        state.status === InvocationStatus.Fulfilled && (
                            <p className="text-sm text-zinc-500 mt-3">
                                Settled on-chain. Result preview unavailable (public RPC) — open
                                the invoke tx on the explorer to verify.
                            </p>
                        )}

                    <div className="mt-3 text-sm text-zinc-400 flex flex-wrap gap-3">
                        <a
                            className="text-emerald-400 underline"
                            href={`${EXPLORER}/tx/${state.txHash}`}
                            target="_blank"
                            rel="noreferrer"
                        >
                            invoke tx
                        </a>
                        {state.fulfillTx && (
                            <a
                                className="text-emerald-400 underline"
                                href={`${EXPLORER}/tx/${state.fulfillTx}`}
                                target="_blank"
                                rel="noreferrer"
                            >
                                fulfillment tx
                            </a>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
}
