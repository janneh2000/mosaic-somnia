#!/usr/bin/env bash
# Adds the "My Agents" owner dashboard:
#   1. web/src/components/OwnedAgentCard.tsx (new)
#   2. web/src/app/my-agents/page.tsx        (new)
#   3. patches web/src/app/layout.tsx to add a nav link
set -euo pipefail

REPO="${REPO:-$HOME/Desktop/mosaic-somnia/mosaic}"
[ -d "$REPO/web/src" ] || { echo "✗ $REPO/web/src not found"; exit 1; }

############################################
# 1. OwnedAgentCard component
############################################
mkdir -p "$REPO/web/src/components"
cat > "$REPO/web/src/components/OwnedAgentCard.tsx" <<'TSX'
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

export function OwnedAgentCard({ id, record }: Props) {
    const [stats, setStats] = useState<ReputationStats | null>(null);
    const cap = decodeCapabilityFromDataUri(record.metadataURI);

    useEffect(() => {
        getReadClient()
            .getReputation(id)
            .then(setStats)
            .catch(() => setStats(null));
    }, [id]);

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
        </div>
    );
}
TSX
echo "✓ wrote web/src/components/OwnedAgentCard.tsx"

############################################
# 2. /my-agents page
############################################
mkdir -p "$REPO/web/src/app/my-agents"
cat > "$REPO/web/src/app/my-agents/page.tsx" <<'TSX'
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
TSX
echo "✓ wrote web/src/app/my-agents/page.tsx"

############################################
# 3. Patch layout.tsx — add "My agents" nav link
############################################
LAYOUT="$REPO/web/src/app/layout.tsx"
cp "$LAYOUT" "$LAYOUT.bak"

python3 - "$LAYOUT" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src = path.read_text()

old = '''                        <nav className="flex gap-4 text-sm text-zinc-300">
                            <a href="/scanner" className="hover:text-emerald-400">
                                Guardian
                            </a>
                            <a href="/register" className="hover:text-emerald-400">
                                Register
                            </a>
                        </nav>'''

new = '''                        <nav className="flex gap-4 text-sm text-zinc-300">
                            <a href="/scanner" className="hover:text-emerald-400">
                                Guardian
                            </a>
                            <a href="/register" className="hover:text-emerald-400">
                                Register
                            </a>
                            <a href="/my-agents" className="hover:text-emerald-400">
                                My agents
                            </a>
                        </nav>'''

if old in src:
    path.write_text(src.replace(old, new))
    print("✓ patched layout.tsx (added 'My agents' nav link)")
elif "/my-agents" in src:
    print("  (layout.tsx already patched)")
else:
    print("✗ couldn't find the nav block in layout.tsx")
    sys.exit(1)
PY

cat <<EOF

──────────────────────────────────────────────────────────────────────
MY AGENTS DASHBOARD INSTALLED.
──────────────────────────────────────────────────────────────────────

Try it locally:
  cd $REPO/web && npm run dev
  open http://localhost:3000/my-agents

Or push and let Vercel rebuild:
  cd $REPO
  git add -A
  git commit -m "feat(web): My agents dashboard with earnings + withdraw"
  git push

What's on the page:
  1. "Your withdrawable earnings: X STT" card with a Withdraw button.
     Pulls MosaicHub.withdrawable(yourAddress) and calls .withdraw() on
     demand. STT lands in your wallet on next block.
  2. Grid of cards for each agent you own (read from agentsByOwner),
     filtered by current owner so transferred-away agents disappear.
     Each card has a status pill (active/paused) and a "manage →" link
     to /agent/[id] where the existing Edit + Transfer panel lives.
  3. Empty state with a CTA to /register when you don't own any agents.
EOF
