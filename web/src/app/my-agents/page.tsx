"use client";
import { useCallback, useEffect, useState } from "react";
import { formatEther, type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import {
    agentRegistryAbi,
    mosaicHubAbi,
    somniaTestnet,
    type AgentRecord
} from "@mosaic/sdk";
import { Wallet } from "@/components/Wallet";
import { OwnedAgentCard } from "@/components/OwnedAgentCard";
import { getReadClient } from "@/lib/client";
import { config } from "@/lib/config";
import { ensureSomniaChain } from "@/lib/ensureChain";

interface Entry {
    id: bigint;
    record: AgentRecord;
}

export default function MyAgentsPage() {
    const { address, isConnected } = useAccount();
    const { writeContractAsync } = useWriteContract();

    const [agents, setAgents] = useState<Entry[]>([]);
    const [loading, setLoading] = useState(false);
    const [withdrawable, setWithdrawable] = useState<bigint>(0n);
    const [busy, setBusy] = useState(false);
    const [tx, setTx] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);

    const refresh = useCallback(async () => {
        if (!address) {
            setAgents([]);
            setWithdrawable(0n);
            return;
        }
        setLoading(true);
        setError(null);
        try {
            const client = getReadClient();
            const ids = (await client.publicClient.readContract({
                address: config.addresses.agentRegistry,
                abi: agentRegistryAbi,
                functionName: "agentsByOwner",
                args: [address as Address]
            })) as bigint[];

            const records = await Promise.all(
                ids.map((id) =>
                    client
                        .getAgent(id)
                        .then((r) => ({ id, record: r }))
                        .catch(() => null)
                )
            );
            const owned = records.filter(
                (e): e is Entry =>
                    !!e && e.record.owner.toLowerCase() === address.toLowerCase()
            );
            setAgents(owned);

            const wd = await client.withdrawable(address as Address);
            setWithdrawable(wd);
        } catch (err) {
            setError(String(err));
        } finally {
            setLoading(false);
        }
    }, [address]);

    useEffect(() => {
        refresh();
    }, [refresh]);

    async function onWithdraw() {
        setBusy(true);
        setTx(null);
        setError(null);
        try {
            const chainNow = await ensureSomniaChain();
            if (chainNow !== somniaTestnet.id) {
                throw new Error(
                    `Wallet on chain ${chainNow}, switch to Somnia Testnet and try again.`
                );
            }
            const hash = await writeContractAsync({
                address: config.addresses.mosaicHub,
                abi: mosaicHubAbi,
                functionName: "withdraw"
            });
            setTx(hash);
            setTimeout(refresh, 3_000);
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
        <div>
            <section className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-3xl font-semibold tracking-tight">
                        Your <span className="text-emerald-400">agents</span>
                    </h1>
                    <p className="text-zinc-300 mt-2">
                        Manage agents you own, see their reputation, and withdraw the STT
                        you've earned from fulfilled invocations.
                    </p>
                </div>
                <Wallet />
            </section>

            {!isConnected && (
                <div className="border rounded-xl p-5 bg-panel">
                    <p className="text-zinc-300">
                        Connect a wallet to see the agents you own. New here?{" "}
                        <a className="text-emerald-400" href="/register">
                            Register your first agent →
                        </a>
                    </p>
                </div>
            )}

            {isConnected && (
                <>
                    <div className="border rounded-xl p-5 bg-panel mb-6">
                        <div className="flex items-center justify-between">
                            <div>
                                <div className="text-zinc-500 text-sm">
                                    Earnings (withdrawable)
                                </div>
                                <div className="text-2xl font-semibold mt-1">
                                    {formatEther(withdrawable)} STT
                                </div>
                                <p className="text-zinc-500 text-sm mt-1">
                                    Pulled from MosaicHub on demand. Earnings accrue every
                                    successful fulfillment.
                                </p>
                            </div>
                            <button
                                className="btn"
                                disabled={busy || withdrawable === 0n}
                                onClick={onWithdraw}
                            >
                                {busy ? "withdrawing…" : "Withdraw"}
                            </button>
                        </div>
                        {tx && (
                            <p className="mt-3 text-sm text-emerald-400">
                                submitted: {tx.slice(0, 10)}… · check Shannon Explorer for
                                confirmation.
                            </p>
                        )}
                        {error && <p className="mt-3 text-sm text-rose-400">{error}</p>}
                    </div>

                    {loading && <p className="text-zinc-500">loading your agents…</p>}
                    {!loading && agents.length === 0 && (
                        <div className="border rounded-xl p-5 bg-panel">
                            <p className="text-zinc-300">
                                You don't own any agents yet.{" "}
                                <a className="text-emerald-400" href="/register">
                                    Register one →
                                </a>
                            </p>
                        </div>
                    )}

                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                        {agents.map((a) => (
                            <OwnedAgentCard
                                key={a.id.toString()}
                                id={a.id}
                                record={a.record}
                            />
                        ))}
                    </div>
                </>
            )}
        </div>
    );
}
