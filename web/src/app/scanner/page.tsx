"use client";
import { useEffect, useState } from "react";
import { isAddress, parseEther, type Address } from "viem";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { guardianAbi } from "@mosaic/sdk";
import { config } from "@/lib/config";
import { getReadClient } from "@/lib/client";
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
        if (!isAddress(target)) {
            alert("invalid address");
            return;
        }
        setBusy(true);
        try {
            // Guardian's pricePerInvocation = 0.05 STT by default
            await writeContractAsync({
                address: config.addresses.guardianModule,
                abi: guardianAbi,
                functionName: "requestScan",
                args: [target as Address],
                value: parseEther("0.05")
            });
            await poll(target as Address);
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

