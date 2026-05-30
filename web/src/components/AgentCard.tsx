"use client";
import { useEffect, useState } from "react";
import { formatEther } from "viem";
import {
    AgentType,
    decodeCapabilityFromDataUri,
    type AgentRecord,
    type ReputationStats
} from "@mosaic/sdk";
import { getReadClient } from "@/lib/client";

interface Props {
    id: bigint;
    record: AgentRecord;
}

function ReputationBadge({ stats }: { stats: ReputationStats | null }) {
    if (!stats || stats.totalInvocations === 0n) {
        return <span className="badge">new</span>;
    }
    const rateBps =
        stats.totalInvocations > 0n
            ? Number((stats.successCount * 10_000n) / stats.totalInvocations)
            : 0;
    const cls = rateBps >= 9_000 ? "badge" : rateBps >= 6_000 ? "badge warn" : "badge bad";
    return (
        <span className={cls}>
            {(rateBps / 100).toFixed(0)}% · {stats.totalInvocations.toString()} runs
        </span>
    );
}

export function AgentCard({ id, record }: Props) {
    const [stats, setStats] = useState<ReputationStats | null>(null);
    const cap = decodeCapabilityFromDataUri(record.metadataURI);
    useEffect(() => {
        getReadClient()
            .getReputation(id)
            .then(setStats)
            .catch(() => setStats(null));
    }, [id]);

    // Liveness heuristic for external agents: one that has run before but has no
    // fulfillment in the last hour likely has an offline runner. Brand-new agents
    // read as "new" (no judgment). Native agents settle via validators, n/a.
    const isExternal = record.agentType === AgentType.EXTERNAL;
    const STALE_AFTER_S = 60 * 60;
    const nowS = Math.floor(Date.now() / 1000);
    const lastSeen = stats && stats.lastUpdatedAt > 0n ? Number(stats.lastUpdatedAt) : null;
    const liveness: "live" | "idle" | null =
        !isExternal || lastSeen === null
            ? null
            : nowS - lastSeen <= STALE_AFTER_S
              ? "live"
              : "idle";

    return (
        <div className="border rounded-xl p-5 bg-panel">
            <div className="flex items-center justify-between">
                <div>
                    <div className="flex items-center gap-2">
                        <div className="text-xl font-semibold">{cap?.name ?? `Agent #${id}`}</div>
                        {liveness === "live" && (
                            <span className="text-emerald-400 text-xs" title="Runner fulfilled within the last hour">
                                ● live
                            </span>
                        )}
                        {liveness === "idle" && (
                            <span className="text-zinc-500 text-xs" title="No fulfillment in the last hour — runner may be offline">
                                ○ idle
                            </span>
                        )}
                    </div>
                    <div className="text-sm text-zinc-500">
                        {record.capabilityTag} ·{" "}
                        {record.agentType === AgentType.NATIVE
                            ? "Somnia native"
                            : "external"}
                    </div>
                </div>
                <ReputationBadge stats={stats} />
            </div>
            <div className="mt-4 text-sm text-zinc-300">
                {cap?.description ?? "no description"}
            </div>
            <div className="mt-4 flex items-center justify-between text-sm">
                <span className="text-zinc-500">
                    {formatEther(record.pricePerInvocation)} STT / invocation
                </span>
                <a className="text-emerald-400" href={`/agent/${id}`}>
                    invoke →
                </a>
            </div>
        </div>
    );
}
