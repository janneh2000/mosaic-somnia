"use client";
import { useCallback, useEffect, useState } from "react";
import { formatEther } from "viem";
import {
    AgentType,
    decodeCapabilityFromDataUri,
    type AgentRecord,
    type ReputationStats,
    type AgentCapabilitySchema
} from "@mosaic/sdk";
import { useParams } from "next/navigation";
import { Wallet } from "@/components/Wallet";
import { EditAgentForm } from "@/components/EditAgentForm";
import { InvokePanel } from "@/components/InvokePanel";
import { getReadClient } from "@/lib/client";

export default function AgentDetailPage() {
    const params = useParams<{ id: string }>();
    const id = BigInt(params.id);
    const [record, setRecord] = useState<AgentRecord | null>(null);
    const [stats, setStats] = useState<ReputationStats | null>(null);
    const [schema, setSchema] = useState<AgentCapabilitySchema | null>(null);

    const refresh = useCallback(() => {
        const client = getReadClient();
        client.getAgent(id).then((r) => {
            setRecord(r);
            setSchema(decodeCapabilityFromDataUri(r.metadataURI));
        });
        client.getReputation(id).then(setStats);
    }, [id]);

    useEffect(() => {
        refresh();
    }, [refresh]);

    if (!record) return <p className="text-zinc-500">loading…</p>;

    const successRate =
        stats && stats.totalInvocations > 0n
            ? Number((stats.successCount * 10_000n) / stats.totalInvocations) / 100
            : null;

    const avgLatency =
        stats && stats.totalInvocations > 0n
            ? Number(stats.cumulativeLatencyMs / stats.totalInvocations)
            : null;

    return (
        <div>
            <section className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-3xl font-semibold tracking-tight">
                        {schema?.name ?? `Agent #${id}`}
                    </h1>
                    <p className="text-zinc-300 mt-2">
                        {schema?.description ?? "no description"}
                    </p>
                </div>
                <Wallet />
            </section>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="border rounded-xl p-5 bg-panel">
                    <div className="text-zinc-500 text-sm">capability</div>
                    <div className="text-xl font-semibold">{record.capabilityTag}</div>
                    <hr className="sep" />
                    <div className="text-sm">
                        <div>
                            <span className="text-zinc-500">type:</span>{" "}
                            {record.agentType === AgentType.NATIVE
                                ? "Somnia native (validator consensus)"
                                : "external (off-chain runner)"}
                        </div>
                        {record.agentType === AgentType.NATIVE && (
                            <div>
                                <span className="text-zinc-500">native id:</span>{" "}
                                {record.nativeAgentId.toString()}
                            </div>
                        )}
                        <div>
                            <span className="text-zinc-500">price:</span>{" "}
                            {formatEther(record.pricePerInvocation)} STT
                        </div>
                        <div>
                            <span className="text-zinc-500">owner:</span> {record.owner}
                        </div>
                        <div>
                            <span className="text-zinc-500">active:</span>{" "}
                            {record.active ? "yes" : "no"}
                        </div>
                    </div>
                </div>

                <div className="border rounded-xl p-5 bg-panel">
                    <div className="text-zinc-500 text-sm">reputation</div>
                    <div className="text-xl font-semibold">
                        {successRate === null ? "no runs yet" : `${successRate.toFixed(0)}%`}
                    </div>
                    <hr className="sep" />
                    {stats && (
                        <div className="text-sm">
                            <div>
                                <span className="text-zinc-500">invocations:</span>{" "}
                                {stats.totalInvocations.toString()}
                            </div>
                            <div>
                                <span className="text-zinc-500">success:</span>{" "}
                                {stats.successCount.toString()}
                            </div>
                            <div>
                                <span className="text-zinc-500">failures:</span>{" "}
                                {stats.failureCount.toString()}
                            </div>
                            <div>
                                <span className="text-zinc-500">timeouts:</span>{" "}
                                {stats.timeoutCount.toString()}
                            </div>
                            {avgLatency !== null && (
                                <div>
                                    <span className="text-zinc-500">avg latency:</span>{" "}
                                    {avgLatency} ms
                                </div>
                            )}
                        </div>
                    )}
                </div>
            </div>

            {record.active && (
                <InvokePanel agentId={id} record={record} schema={schema} />
            )}

            {schema && (
                <div className="border rounded-xl p-5 bg-panel mt-6">
                    <div className="text-zinc-500 text-sm">capability schema (MCP-compatible)</div>
                    <pre className="pre mt-2">{JSON.stringify(schema, null, 2)}</pre>
                </div>
            )}

            <EditAgentForm
                agentId={id}
                record={record}
                schema={schema}
                onUpdated={() => {
                    // Wait a couple seconds for the tx to settle, then re-read.
                    setTimeout(refresh, 3_000);
                }}
            />
        </div>
    );
}
