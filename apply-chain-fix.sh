#!/usr/bin/env bash
# Applies the Phantom/MetaMask chain-switch fix to your Desktop mosaic repo.
# Run from anywhere — it cd's into the repo by absolute path.
set -eo pipefail

REPO="$HOME/Desktop/mosaic-somnia/mosaic"
if [ ! -d "$REPO/web/src" ]; then
    echo "expected $REPO/web/src to exist — adjust REPO at top of script" >&2
    exit 1
fi

cd "$REPO"

# ---------- 1) NEW: web/src/lib/ensureChain.ts ----------
cat > web/src/lib/ensureChain.ts <<'TSEOF'
"use client";

import { somniaTestnet } from "@mosaic/sdk";

/**
 * Direct-to-provider chain switcher. Bypasses wagmi entirely because some
 * wallets (notably Phantom EVM and any provider that proxies window.ethereum
 * from another extension) don't reliably report a successful chain switch
 * back to wagmi via the eth_chainId event, leaving wagmi's `useChainId` stuck
 * on the old value and triggering a false-positive chain-mismatch error.
 *
 * Returns the chainId reported by the wallet after the switch (as a number).
 */
export async function ensureSomniaChain(): Promise<number> {
    const eth = (
        globalThis as unknown as {
            ethereum?: {
                request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
            };
        }
    ).ethereum;
    if (!eth) {
        throw new Error("No injected wallet provider found.");
    }

    const targetHex = "0x" + somniaTestnet.id.toString(16); // 50312 -> 0xc488

    try {
        const current = (await eth.request({ method: "eth_chainId" })) as string;
        if (current && parseInt(current, 16) === somniaTestnet.id) {
            return somniaTestnet.id;
        }
    } catch {
        /* fall through to the switch attempt */
    }

    try {
        await eth.request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: targetHex }]
        });
    } catch (err) {
        const code = (err as { code?: number }).code;
        if (code === 4902 || code === -32603) {
            await eth.request({
                method: "wallet_addEthereumChain",
                params: [
                    {
                        chainId: targetHex,
                        chainName: "Somnia Testnet",
                        nativeCurrency: {
                            name: "Somnia Test Token",
                            symbol: "STT",
                            decimals: 18
                        },
                        rpcUrls: ["https://api.infra.testnet.somnia.network/"],
                        blockExplorerUrls: ["https://shannon-explorer.somnia.network"]
                    }
                ]
            });
            await eth.request({
                method: "wallet_switchEthereumChain",
                params: [{ chainId: targetHex }]
            });
        } else {
            throw err;
        }
    }

    const after = (await eth.request({ method: "eth_chainId" })) as string;
    return parseInt(after, 16);
}
TSEOF

# ---------- 2) REWRITE: web/src/app/scanner/page.tsx ----------
cat > web/src/app/scanner/page.tsx <<'TSEOF'
"use client";
import { useState } from "react";
import { isAddress, parseEther, type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { guardianAbi, somniaTestnet } from "@mosaic/sdk";
import { config } from "@/lib/config";
import { getReadClient } from "@/lib/client";
import { ensureSomniaChain } from "@/lib/ensureChain";
import { Wallet } from "@/components/Wallet";

interface Report {
    target: Address;
    codeSize: bigint;
    hasSelfdestruct: boolean;
    hasDelegatecall: boolean;
    onchainRiskScore: number;
    offchainRiskScore: number;
    compositeRiskScore: number;
    generatedAt: bigint;
    offchainDetails: `0x${string}`;
}

function riskBadge(score: number) {
    if (score <= 30) return <span className="badge">{score} · low</span>;
    if (score <= 60) return <span className="badge warn">{score} · medium</span>;
    return <span className="badge bad">{score} · high</span>;
}

export default function ScannerPage() {
    const [target, setTarget] = useState("");
    const [report, setReport] = useState<Report | null>(null);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const { isConnected } = useAccount();
    const { writeContractAsync } = useWriteContract();

    async function poll(addr: Address) {
        const client = getReadClient();
        for (let i = 0; i < 30; i++) {
            const raw = (await client.publicClient.readContract({
                address: config.addresses.guardianModule,
                abi: guardianAbi,
                functionName: "lastReport",
                args: [addr]
            })) as unknown as [
                Address,
                bigint,
                boolean,
                boolean,
                number,
                number,
                number,
                bigint,
                `0x${string}`
            ];
            if (raw[7] !== 0n) {
                setReport({
                    target: raw[0],
                    codeSize: raw[1],
                    hasSelfdestruct: raw[2],
                    hasDelegatecall: raw[3],
                    onchainRiskScore: raw[4],
                    offchainRiskScore: raw[5],
                    compositeRiskScore: raw[6],
                    generatedAt: raw[7],
                    offchainDetails: raw[8]
                });
                return;
            }
            await new Promise((r) => setTimeout(r, 2_000));
        }
    }

    async function onScan() {
        setReport(null);
        setError(null);
        if (!isAddress(target)) {
            setError("invalid address");
            return;
        }
        setBusy(true);
        try {
            const active = await ensureSomniaChain();
            if (active !== somniaTestnet.id) {
                throw new Error(
                    `Wallet still on chain ${active} after switch. Open your wallet, switch to Somnia Testnet manually, then try again.`
                );
            }

            const hash = await writeContractAsync({
                address: config.addresses.guardianModule,
                abi: guardianAbi,
                functionName: "requestScan",
                args: [target as Address],
                value: parseEther("0.05")
            });
            console.log("[scan] tx submitted:", hash);
            await poll(target as Address);
        } catch (err) {
            console.error("[scan] failed:", err);
            const msg = (err as { shortMessage?: string; message?: string })?.shortMessage
                ?? (err as Error)?.message
                ?? String(err);
            setError(msg);
        } finally {
            setBusy(false);
        }
    }

    let offchainParsed: unknown = null;
    if (report?.offchainDetails && report.offchainDetails !== "0x") {
        try {
            const str = Buffer.from(report.offchainDetails.slice(2), "hex").toString("utf8");
            offchainParsed = JSON.parse(str);
        } catch {
            /* ignore */
        }
    }

    return (
        <div>
            <section className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-3xl font-semibold tracking-tight">
                        <span className="text-emerald-400">Protocol Guardian</span>
                    </h1>
                    <p className="text-zinc-300 mt-2">
                        Mosaic's flagship security agent. Scans a deployed contract for
                        risky opcodes (SELFDESTRUCT, DELEGATECALL) and combines on-chain
                        heuristics with an off-chain runner's structured assessment.
                    </p>
                </div>
                <Wallet />
            </section>

            <div className="border rounded-xl p-5 bg-panel">
                <div className="flex gap-3">
                    <input
                        className="input"
                        placeholder="0x… contract address"
                        value={target}
                        onChange={(e) => setTarget(e.target.value)}
                    />
                    <button className="btn" disabled={busy || !isConnected} onClick={onScan}>
                        {busy ? "Scanning…" : "Request scan (0.05 STT)"}
                    </button>
                </div>
                {!isConnected && (
                    <p className="mt-2 text-sm text-zinc-500">
                        connect your wallet to request a scan.
                    </p>
                )}
                {error && (
                    <p className="mt-2 text-sm text-rose-400">{error}</p>
                )}
            </div>

            {report && (
                <div className="mt-6 border rounded-xl p-5 bg-panel">
                    <div className="flex items-center justify-between">
                        <div className="text-xl font-semibold">scan report</div>
                        {riskBadge(report.compositeRiskScore)}
                    </div>
                    <hr className="sep" />
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6 text-sm">
                        <div>
                            <div className="text-zinc-500">target</div>
                            <div>{report.target}</div>
                            <div className="mt-2 text-zinc-500">code size</div>
                            <div>{report.codeSize.toString()} bytes</div>
                        </div>
                        <div>
                            <div className="text-zinc-500">on-chain heuristic</div>
                            <div>{report.onchainRiskScore}</div>
                            <div className="mt-2 text-zinc-500">off-chain assessment</div>
                            <div>
                                {report.offchainRiskScore === 255
                                    ? "unavailable"
                                    : report.offchainRiskScore}
                            </div>
                        </div>
                    </div>
                    <div className="mt-4 flex gap-3">
                        {report.hasSelfdestruct && (
                            <span className="badge bad">SELFDESTRUCT</span>
                        )}
                        {report.hasDelegatecall && (
                            <span className="badge warn">DELEGATECALL</span>
                        )}
                    </div>
                    {offchainParsed ? (
                        <pre className="pre mt-4">
                            {JSON.stringify(offchainParsed, null, 2)}
                        </pre>
                    ) : null}
                </div>
            )}
        </div>
    );
}
TSEOF

# ---------- 3) REWRITE: web/src/app/register/page.tsx ----------
cat > web/src/app/register/page.tsx <<'TSEOF'
"use client";
import { useState } from "react";
import { parseEther } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import {
    AgentType,
    agentRegistryAbi,
    encodeCapabilityAsDataUri,
    somniaTestnet
} from "@mosaic/sdk";
import { config } from "@/lib/config";
import { ensureSomniaChain } from "@/lib/ensureChain";
import { Wallet } from "@/components/Wallet";

export default function RegisterPage() {
    const [name, setName] = useState("");
    const [tag, setTag] = useState("");
    const [description, setDescription] = useState("");
    const [price, setPrice] = useState("0.01");
    const [agentType, setAgentType] = useState<AgentType>(AgentType.EXTERNAL);
    const [nativeId, setNativeId] = useState("");
    const [busy, setBusy] = useState(false);
    const [tx, setTx] = useState<string | null>(null);

    const { isConnected } = useAccount();
    const { writeContractAsync } = useWriteContract();

    async function onSubmit(e: React.FormEvent) {
        e.preventDefault();
        setBusy(true);
        setTx(null);
        try {
            const schema = {
                name,
                kind: tag,
                version: "1.0.0",
                description,
                methods: [
                    {
                        name: "invoke",
                        args: [{ name: "payload", type: "bytes" }],
                        returns: [{ name: "result", type: "bytes" }]
                    }
                ]
            };
            const uri = encodeCapabilityAsDataUri(schema);
            const active = await ensureSomniaChain();
            if (active !== somniaTestnet.id) {
                throw new Error(
                    `Wallet still on chain ${active} after switch. Open your wallet, switch to Somnia Testnet manually, then try again.`
                );
            }
            const hash = await writeContractAsync({
                address: config.addresses.agentRegistry,
                abi: agentRegistryAbi,
                functionName: "register",
                args: [
                    agentType,
                    agentType === AgentType.NATIVE ? BigInt(nativeId || "0") : 0n,
                    parseEther(price || "0"),
                    uri,
                    tag
                ]
            });
            setTx(hash);
        } catch (err) {
            alert(String(err));
        } finally {
            setBusy(false);
        }
    }

    return (
        <div>
            <section className="flex items-center justify-between mb-6">
                <div>
                    <h1 className="text-3xl font-semibold tracking-tight">
                        Register an <span className="text-emerald-400">agent</span>
                    </h1>
                    <p className="text-zinc-300 mt-2">
                        Any wallet can register an external (MCP-style) agent or wrap a
                        Somnia native agent. Capability metadata is stored on-chain as a
                        data URI.
                    </p>
                </div>
                <Wallet />
            </section>

            <form onSubmit={onSubmit} className="border rounded-xl p-5 bg-panel grid gap-3">
                <label className="text-sm">
                    name
                    <input
                        className="input mt-2"
                        required
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        placeholder="MyCoolAgent"
                    />
                </label>
                <label className="text-sm">
                    capability tag (one word, lowercase)
                    <input
                        className="input mt-2"
                        required
                        value={tag}
                        onChange={(e) => setTag(e.target.value)}
                        placeholder="oracle | security | summarizer | …"
                    />
                </label>
                <label className="text-sm">
                    description
                    <textarea
                        className="textarea mt-2"
                        value={description}
                        onChange={(e) => setDescription(e.target.value)}
                        placeholder="what does your agent do?"
                    />
                </label>
                <label className="text-sm">
                    price per invocation (STT)
                    <input
                        className="input mt-2"
                        type="number"
                        step="0.001"
                        value={price}
                        onChange={(e) => setPrice(e.target.value)}
                    />
                </label>
                <label className="text-sm">
                    agent type
                    <select
                        className="select mt-2"
                        value={agentType}
                        onChange={(e) => setAgentType(Number(e.target.value) as AgentType)}
                    >
                        <option value={AgentType.EXTERNAL}>external (off-chain runner)</option>
                        <option value={AgentType.NATIVE}>native (Somnia validator-consensus)</option>
                    </select>
                </label>
                {agentType === AgentType.NATIVE && (
                    <label className="text-sm">
                        native Somnia agent id
                        <input
                            className="input mt-2"
                            value={nativeId}
                            onChange={(e) => setNativeId(e.target.value)}
                            placeholder="e.g. 12345678901234567890"
                        />
                    </label>
                )}
                <button className="btn" type="submit" disabled={busy || !isConnected}>
                    {busy ? "registering…" : "Register agent"}
                </button>
                {tx && (
                    <p className="text-sm text-emerald-400">
                        submitted: {tx.slice(0, 10)}… · check Shannon Explorer for confirmation.
                    </p>
                )}
            </form>
        </div>
    );
}
TSEOF

# ---------- 4) REWRITE: web/src/components/Wallet.tsx ----------
cat > web/src/components/Wallet.tsx <<'TSEOF'
"use client";
import { useAccount, useConnect, useDisconnect, useChainId } from "wagmi";
import { somniaTestnet } from "@mosaic/sdk";
import { ensureSomniaChain } from "@/lib/ensureChain";

export function Wallet() {
    const { address, isConnected } = useAccount();
    const { connect, connectors, isPending } = useConnect();
    const { disconnect } = useDisconnect();
    const chainId = useChainId();
    const wrongChain = isConnected && chainId !== somniaTestnet.id;

    if (!isConnected) {
        return (
            <button
                className="btn"
                disabled={isPending}
                onClick={() => connect({ connector: connectors[0]! })}
            >
                {isPending ? "Connecting…" : "Connect Wallet"}
            </button>
        );
    }
    if (wrongChain) {
        return (
            <button
                className="btn"
                onClick={() =>
                    ensureSomniaChain().catch((err) => {
                        console.error("[wallet] switch failed:", err);
                        alert(
                            "Switch failed — open your wallet and switch to Somnia Testnet manually."
                        );
                    })
                }
            >
                Switch to Somnia Testnet
            </button>
        );
    }
    return (
        <div className="flex gap-3 items-center">
            <span className="badge">
                {address?.slice(0, 6)}…{address?.slice(-4)}
            </span>
            <button className="btn" onClick={() => disconnect()}>
                Disconnect
            </button>
        </div>
    );
}
TSEOF

echo "all 4 files updated. commit + push:"
echo "  cd $REPO"
echo "  git add -A && git commit -m 'fix(web): direct provider chain switch + drop wagmi chainId pin'"
echo "  git push"
