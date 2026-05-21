"use client";
import { useState } from "react";
import { parseEther } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import {
    AgentType,
    agentRegistryAbi,
    encodeCapabilityAsDataUri
} from "@mosaic/sdk";
import { config } from "@/lib/config";
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
