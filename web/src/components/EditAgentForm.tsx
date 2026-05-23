"use client";
import { useState } from "react";
import { formatEther, parseEther, isAddress, type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import {
    agentRegistryAbi,
    encodeCapabilityAsDataUri,
    somniaTestnet,
    type AgentCapabilitySchema,
    type AgentRecord
} from "@mosaic/sdk";
import { config } from "@/lib/config";
import { ensureSomniaChain } from "@/lib/ensureChain";

interface Props {
    agentId: bigint;
    record: AgentRecord;
    schema: AgentCapabilitySchema | null;
    onUpdated?: () => void;
}

export function EditAgentForm({ agentId, record, schema, onUpdated }: Props) {
    const { address } = useAccount();
    const { writeContractAsync } = useWriteContract();

    const [name, setName] = useState(schema?.name ?? "");
    const [description, setDescription] = useState(schema?.description ?? "");
    const [price, setPrice] = useState(formatEther(record.pricePerInvocation));
    const [active, setActive] = useState(record.active);
    const [transferTo, setTransferTo] = useState("");

    const [busy, setBusy] = useState<"save" | "transfer" | null>(null);
    const [tx, setTx] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);

    const isOwner =
        !!address && record.owner.toLowerCase() === address.toLowerCase();
    if (!isOwner) return null;

    async function onUpdate(e: React.FormEvent) {
        e.preventDefault();
        setBusy("save");
        setTx(null);
        setError(null);
        try {
            const nextSchema: AgentCapabilitySchema = {
                name,
                kind: schema?.kind ?? record.capabilityTag,
                version: schema?.version ?? "1.0.0",
                description: description || undefined,
                methods: schema?.methods ?? [],
                runner: schema?.runner
            };
            const newMetadataURI = encodeCapabilityAsDataUri(nextSchema);

            const chainNow = await ensureSomniaChain();
            if (chainNow !== somniaTestnet.id) {
                throw new Error(
                    `Wallet still on chain ${chainNow}, switch to Somnia Testnet and try again.`
                );
            }

            const hash = await writeContractAsync({
                address: config.addresses.agentRegistry,
                abi: agentRegistryAbi,
                functionName: "update",
                args: [agentId, parseEther(price || "0"), newMetadataURI, active]
            });
            setTx(hash);
            onUpdated?.();
        } catch (err) {
            const msg =
                (err as { shortMessage?: string; message?: string })?.shortMessage ??
                (err as Error)?.message ??
                String(err);
            setError(msg);
        } finally {
            setBusy(null);
        }
    }

    async function onTransfer() {
        if (!isAddress(transferTo)) {
            setError("invalid recipient address");
            return;
        }
        if (
            !confirm(
                `Transfer agent #${agentId} ownership to ${transferTo}?\nThis is irreversible from the UI — the recipient will need to call transferAgent to give it back.`
            )
        ) {
            return;
        }
        setBusy("transfer");
        setTx(null);
        setError(null);
        try {
            const chainNow = await ensureSomniaChain();
            if (chainNow !== somniaTestnet.id) {
                throw new Error(
                    `Wallet still on chain ${chainNow}, switch to Somnia Testnet and try again.`
                );
            }
            const hash = await writeContractAsync({
                address: config.addresses.agentRegistry,
                abi: agentRegistryAbi,
                functionName: "transferAgent",
                args: [agentId, transferTo as Address]
            });
            setTx(hash);
            setTransferTo("");
            onUpdated?.();
        } catch (err) {
            const msg =
                (err as { shortMessage?: string; message?: string })?.shortMessage ??
                (err as Error)?.message ??
                String(err);
            setError(msg);
        } finally {
            setBusy(null);
        }
    }

    return (
        <div className="border rounded-xl p-5 bg-panel mt-6">
            <div className="flex items-center justify-between">
                <div className="text-xl font-semibold">Edit agent</div>
                <span className="text-xs text-emerald-400 border border-emerald-400/40 rounded-full px-2 py-0.5">
                    you own this
                </span>
            </div>
            <hr className="sep" />

            <form onSubmit={onUpdate} className="grid gap-3">
                <label className="text-sm">
                    name
                    <input
                        className="input mt-2"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        placeholder="agent display name"
                    />
                </label>
                <label className="text-sm">
                    description
                    <textarea
                        className="textarea mt-2"
                        value={description}
                        onChange={(e) => setDescription(e.target.value)}
                        placeholder="what this agent does — shown on the marketplace card"
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
                <label className="text-sm flex items-center gap-2 mt-1">
                    <input
                        type="checkbox"
                        checked={active}
                        onChange={(e) => setActive(e.target.checked)}
                    />
                    active &middot;{" "}
                    <span className="text-zinc-500">
                        uncheck to pause invocations without losing reputation history
                    </span>
                </label>
                <button className="btn" type="submit" disabled={busy !== null}>
                    {busy === "save" ? "saving…" : "Save changes"}
                </button>
            </form>

            <hr className="sep" />

            <div className="text-zinc-500 text-sm mb-2">danger zone</div>
            <div className="flex flex-col sm:flex-row gap-3">
                <input
                    className="input flex-1"
                    placeholder="0x… new owner address"
                    value={transferTo}
                    onChange={(e) => setTransferTo(e.target.value)}
                />
                <button
                    className="btn"
                    type="button"
                    disabled={busy !== null || transferTo.length === 0}
                    onClick={onTransfer}
                >
                    {busy === "transfer" ? "transferring…" : "Transfer ownership"}
                </button>
            </div>

            {tx && (
                <p className="mt-3 text-sm text-emerald-400">
                    submitted: {tx.slice(0, 10)}… · check Shannon Explorer for confirmation.
                </p>
            )}
            {error && <p className="mt-3 text-sm text-rose-400">{error}</p>}
        </div>
    );
}
