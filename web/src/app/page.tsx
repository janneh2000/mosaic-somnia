"use client";
import { useEffect, useState } from "react";
import type { AgentRecord } from "@mosaic/sdk";
import { AgentCard } from "@/components/AgentCard";
import { Wallet } from "@/components/Wallet";
import { getReadClient } from "@/lib/client";

interface Entry {
    id: bigint;
    record: AgentRecord;
}

export default function HomePage() {
    const [agents, setAgents] = useState<Entry[]>([]);
    const [loading, setLoading] = useState(true);
    const [err, setErr] = useState<string | null>(null);

    useEffect(() => {
        getReadClient()
            .listAll()
            .then((entries) => {
                setAgents(entries.filter((e) => e.record.active));
                setLoading(false);
            })
            .catch((e) => {
                setErr(String(e));
                setLoading(false);
            });
    }, []);

    return (
        <div>
            <section className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-3xl font-semibold tracking-tight">
                        Discover, invoke, and compose <span className="text-emerald-400">agents</span> on Somnia
                    </h1>
                    <p className="text-zinc-300 mt-2">
                        Mosaic is an on-chain marketplace for autonomous agents — MCP-style
                        external agents and Somnia's native validator-consensus agents, in
                        one composable layer.
                    </p>
                </div>
                <Wallet />
            </section>

            {loading && <p className="text-zinc-500">loading agents…</p>}
            {err && <p className="text-rose-400">error: {err}</p>}
            {!loading && agents.length === 0 && (
                <p className="text-zinc-500">no agents registered yet — be the first.</p>
            )}

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {agents.map((a) => (
                    <AgentCard key={a.id.toString()} id={a.id} record={a.record} />
                ))}
            </div>
        </div>
    );
}
