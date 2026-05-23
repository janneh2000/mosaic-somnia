#!/usr/bin/env bash
# Adds the "edit my agent" flow to the Mosaic frontend.
#   1. Extends sdk/src/abi.ts with update/transferAgent/exists + 2 events.
#   2. Writes web/src/components/EditAgentForm.tsx (owner-only edit panel).
#   3. Patches web/src/app/agent/[id]/page.tsx to render it.
set -euo pipefail

REPO="${REPO:-$HOME/Desktop/mosaic-somnia/mosaic}"
[ -d "$REPO" ] || { echo "✗ $REPO not found"; exit 1; }

############################################
# 1. SDK abi.ts — append missing fns + events to agentRegistryAbi
############################################
SDK_ABI="$REPO/sdk/src/abi.ts"
cp "$SDK_ABI" "$SDK_ABI.bak"

python3 - "$SDK_ABI" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src = path.read_text()

# We anchor on the existing AgentRegistered event followed by the closing `] as const;`
old = """    {
        type: "event",
        name: "AgentRegistered",
        inputs: [
            { name: "agentId", type: "uint256", indexed: true },
            { name: "owner", type: "address", indexed: true },
            { name: "agentType", type: "uint8", indexed: false },
            { name: "nativeAgentId", type: "uint256", indexed: false },
            { name: "pricePerInvocation", type: "uint256", indexed: false },
            { name: "capabilityTag", type: "string", indexed: false },
            { name: "metadataURI", type: "string", indexed: false }
        ]
    }
] as const;"""

new = """    {
        type: "function",
        name: "update",
        stateMutability: "nonpayable",
        inputs: [
            { name: "agentId", type: "uint256" },
            { name: "pricePerInvocation", type: "uint256" },
            { name: "metadataURI", type: "string" },
            { name: "active", type: "bool" }
        ],
        outputs: []
    },
    {
        type: "function",
        name: "transferAgent",
        stateMutability: "nonpayable",
        inputs: [
            { name: "agentId", type: "uint256" },
            { name: "to", type: "address" }
        ],
        outputs: []
    },
    {
        type: "function",
        name: "exists",
        stateMutability: "view",
        inputs: [{ name: "agentId", type: "uint256" }],
        outputs: [{ type: "bool" }]
    },
    {
        type: "event",
        name: "AgentRegistered",
        inputs: [
            { name: "agentId", type: "uint256", indexed: true },
            { name: "owner", type: "address", indexed: true },
            { name: "agentType", type: "uint8", indexed: false },
            { name: "nativeAgentId", type: "uint256", indexed: false },
            { name: "pricePerInvocation", type: "uint256", indexed: false },
            { name: "capabilityTag", type: "string", indexed: false },
            { name: "metadataURI", type: "string", indexed: false }
        ]
    },
    {
        type: "event",
        name: "AgentUpdated",
        inputs: [
            { name: "agentId", type: "uint256", indexed: true },
            { name: "pricePerInvocation", type: "uint256", indexed: false },
            { name: "metadataURI", type: "string", indexed: false },
            { name: "active", type: "bool", indexed: false }
        ]
    },
    {
        type: "event",
        name: "AgentTransferred",
        inputs: [
            { name: "agentId", type: "uint256", indexed: true },
            { name: "from", type: "address", indexed: true },
            { name: "to", type: "address", indexed: true }
        ]
    }
] as const;"""

if old in src:
    path.write_text(src.replace(old, new))
    print("✓ extended agentRegistryAbi (update / transferAgent / exists + 2 events)")
elif '"update"' in src and '"transferAgent"' in src:
    print("  (sdk/src/abi.ts already patched, skipping)")
else:
    print("✗ couldn't find anchor block in sdk/src/abi.ts — check manually")
    sys.exit(1)
PY

############################################
# 2. EditAgentForm component
############################################
mkdir -p "$REPO/web/src/components"
cat > "$REPO/web/src/components/EditAgentForm.tsx" <<'TSX'
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
TSX
echo "✓ wrote web/src/components/EditAgentForm.tsx"

############################################
# 3. Patch the agent detail page to render the form
############################################
PAGE="$REPO/web/src/app/agent/[id]/page.tsx"
cp "$PAGE" "$PAGE.bak"

python3 - "$PAGE" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src = path.read_text()

# Patch 1: add useCallback to imports + EditAgentForm import, swap useEffect for refresh callback
old_imports = """"use client";
import { useEffect, useState } from "react";
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
import { getReadClient } from "@/lib/client";

export default function AgentDetailPage() {
    const params = useParams<{ id: string }>();
    const id = BigInt(params.id);
    const [record, setRecord] = useState<AgentRecord | null>(null);
    const [stats, setStats] = useState<ReputationStats | null>(null);
    const [schema, setSchema] = useState<AgentCapabilitySchema | null>(null);

    useEffect(() => {
        const client = getReadClient();
        client.getAgent(id).then((r) => {
            setRecord(r);
            setSchema(decodeCapabilityFromDataUri(r.metadataURI));
        });
        client.getReputation(id).then(setStats);
    }, [id]);"""

new_imports = """"use client";
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
    }, [refresh]);"""

if old_imports in src:
    src = src.replace(old_imports, new_imports)
elif "EditAgentForm" in src:
    print("  (page already patched, will only adjust if needed)")
else:
    print("✗ couldn't find the import/effect block in agent detail page")
    sys.exit(1)

# Patch 2: insert <EditAgentForm /> just before the final </div>
old_tail = """            {schema && (
                <div className=\"border rounded-xl p-5 bg-panel mt-6\">
                    <div className=\"text-zinc-500 text-sm\">capability schema (MCP-compatible)</div>
                    <pre className=\"pre mt-2\">{JSON.stringify(schema, null, 2)}</pre>
                </div>
            )}
        </div>
    );
}"""

new_tail = """            {schema && (
                <div className=\"border rounded-xl p-5 bg-panel mt-6\">
                    <div className=\"text-zinc-500 text-sm\">capability schema (MCP-compatible)</div>
                    <pre className=\"pre mt-2\">{JSON.stringify(schema, null, 2)}</pre>
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
}"""

if old_tail in src:
    src = src.replace(old_tail, new_tail)
elif "<EditAgentForm" in src:
    pass  # already inserted
else:
    print("✗ couldn't find the tail block — page may have been edited; check manually")
    sys.exit(1)

path.write_text(src)
print("✓ patched web/src/app/agent/[id]/page.tsx (renders EditAgentForm)")
PY

cat <<EOF

──────────────────────────────────────────────────────────────────────
EDIT-AGENT FLOW INSTALLED.
──────────────────────────────────────────────────────────────────────

Next steps:
  1. Restart the dev server if running locally:
       cd $REPO/web && npm run dev

  2. Or push and let Vercel rebuild:
       cd $REPO
       git add -A
       git commit -m "feat(web): owner-only edit & transfer flow for agents"
       git push

  3. Open any /agent/<id> page. If your connected wallet equals the
     agent owner, an "Edit agent" panel appears under the capability
     schema, with form fields for name / description / price / active
     and a Transfer Ownership block.

What it touches on-chain:
  - "Save changes" → AgentRegistry.update(id, price, newMetadataURI, active)
  - "Transfer ownership" → AgentRegistry.transferAgent(id, recipient)

Note: AgentRegistry.update preserves capability tag and type (those
are immutable). To rename the capability tag you'd have to re-register.
EOF
