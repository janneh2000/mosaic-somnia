"use client";
import { useEffect, useState } from "react";
import { formatEther } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import {
    AgentType,
    agentRegistryAbi,
    decodeCapabilityFromDataUri,
    somniaTestnet,
    type AgentRecord,
    type ReputationStats
} from "@mosaic/sdk";
import { getReadClient } from "@/lib/client";
import { config } from "@/lib/config";
import { ensureSomniaChain } from "@/lib/ensureChain";

interface Props {
    id: bigint;
    record: AgentRecord;
    /** Called after a successful pause/resume tx so the parent can refresh. */
    onChanged?: () => void;
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

/**
 * Variant of AgentCard for the owner dashboard. Shows the same info as the
 * marketplace card plus an "active/paused" badge, a one-click Pause/Resume
 * button (calls AgentRegistry.update with the active flag flipped), and a
 * "Manage" link to /agent/[id] for full edits + transfer.
 *
 * Pausing is the soft-delete: the home marketplace filters on `active === true`
 * (see app/page.tsx), so a paused agent disappears from the public grid while
 * its on-chain ID, metadata, and reputation history stay intact.
 */
export function OwnedAgentCard({ id, record, onChanged }: Props) {
    const [stats, setStats] = useState<ReputationStats | null>(null);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [tx, setTx] = useState<string | null>(null);

    const { address } = useAccount();
    const { writeContractAsync } = useWriteContract();
    const cap = decodeCapabilityFromDataUri(record.metadataURI);
    const isOwner =
        address && address.toLowerCase() === record.owner.toLowerCase();

    useEffect(() => {
        getReadClient()
            .getReputation(id)
            .then(setStats)
            .catch(() => setStats(null));
    }, [id]);

    async function togglePaused() {
        setBusy(true);
        setError(null);
        setTx(null);
        try {
            const chainNow = await ensureSomniaChain();
            if (chainNow !== somniaTestnet.id) {
                throw new Error(
                    `Wallet on chain ${chainNow}, switch to Somnia Testnet and try again.`
                );
            }
            const hash = await writeContractAsync({
                address: config.addresses.agentRegistry,
                abi: agentRegistryAbi,
                functionName: "update",
                args: [
                    id,
                    record.pricePerInvocation,
                    record.metadataURI,
                    !record.active
                ]
            });
            setTx(hash);
            // Give the chain a moment, then bubble up so MyAgentsPage refetches.
            setTimeout(() => onChanged?.(), 3_000);
        } catch (err) {
            const msg =
                (err as { shortMessage?: string; message?: string })?.shortMessage ??
                (err as Error)?.message ??
                String(err);
            setError(msg);
        } finally {
            setBusy(false);
        }
    }

    return (
        <div
            className={`border rounded-xl p-5 bg-panel ${
                record.active ? "" : "opacity-60"
            }`}
        >
            <div className="flex items-center justify-between">
                <div>
                    <div className="text-xl font-semibold">
                        {cap?.name ?? `Agent #${id}`}
                    </div>
                    <div className="text-sm text-zinc-500">
                        {record.capabilityTag} ·{" "}
                        {record.agentType === AgentType.NATIVE
                            ? "Somnia native"
                            : "external"}
                        {" · "}
                        <span
                            className={record.active ? "text-emerald-400" : "text-rose-400"}
                        >
                            {record.active ? "active" : "paused"}
                        </span>
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
                    manage →
                </a>
            </div>

            {isOwner && (
                <div className="mt-4 flex items-center justify-between border-t border-zinc-800 pt-4">
                    <span className="text-xs text-zinc-500">
                        {record.active
                            ? "Pause to remove from the public marketplace."
                            : "Resume to list this agent again."}
                    </span>
                    <button
                        className="btn"
                        onClick={togglePaused}
                        disabled={busy}
                        title={
                            record.active
                                ? "Soft-delete: hides from marketplace, keeps reputation"
                                : "Re-list this agent on the marketplace"
                        }
                    >
                        {busy
                            ? record.active
                                ? "pausing…"
                                : "resuming…"
                            : record.active
                            ? "Pause"
                            : "Resume"}
                    </button>
                </div>
            )}

            {tx && (
                <p className="mt-3 text-xs text-emerald-400">
                    submitted: {tx.slice(0, 10)}… · refreshing…
                </p>
            )}
            {error && <p className="mt-3 text-xs text-rose-400">{error}</p>}
        </div>
    );
}
