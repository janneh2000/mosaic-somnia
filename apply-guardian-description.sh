#!/usr/bin/env bash
# Fixes the "no description" on the ProtocolGuardian marketplace card.
#   1. patches scripts/deploy-manual.sh so future deploys include a description
#   2. writes agents/src/updateGuardianMetadata.ts to fix the LIVE agent on-chain
set -euo pipefail

REPO="${REPO:-$HOME/Desktop/mosaic-somnia/mosaic}"
[ -d "$REPO" ] || { echo "✗ $REPO not found"; exit 1; }

############################################
# 1. deploy-manual.sh — replace the metadata literal
############################################
DEPLOY="$REPO/scripts/deploy-manual.sh"
cp "$DEPLOY" "$DEPLOY.bak"

python3 - "$DEPLOY" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src = path.read_text()

old = "METADATA='data:application/json,%7B%22name%22%3A%22ProtocolGuardian%22%2C%22kind%22%3A%22security%22%2C%22version%22%3A%221.0.0%22%7D'"
new = (
    "# ProtocolGuardian capability schema. Keep in sync with the marketplace\n"
    "    # card copy on the web app (web/src/components/AgentCard.tsx reads the\n"
    "    # `description` field).\n"
    "    METADATA='data:application/json,%7B%22name%22%3A%22ProtocolGuardian%22%2C%22kind%22%3A%22security%22%2C%22version%22%3A%221.0.0%22%2C%22description%22%3A%22Mosaic%27s%20flagship%20security%20agent.%20Scans%20a%20deployed%20contract%20for%20risky%20opcodes%20%28SELFDESTRUCT%2C%20DELEGATECALL%29%20and%20combines%20on-chain%20heuristics%20with%20an%20off-chain%20runner%27s%20structured%20assessment.%22%7D'"
)

if old in src:
    path.write_text(src.replace(old, "    " + new))
    print("✓ patched deploy-manual.sh (Guardian metadata now includes description)")
elif "%22description%22" in src:
    print("  (deploy-manual.sh already patched, skipping)")
else:
    print("✗ couldn't find the METADATA literal in deploy-manual.sh")
    sys.exit(1)
PY

############################################
# 2. write the one-shot updater
############################################
cat > "$REPO/agents/src/updateGuardianMetadata.ts" <<'TS'
/**
 * Patches the live Guardian agent's metadataURI on AgentRegistry so the
 * marketplace card shows a real description instead of "no description".
 *
 * Callable by anyone holding the agent-owner key (after the ownership-transfer
 * fix, that's the wallet whose private key is AGENT_PRIVATE_KEY in .env).
 */
import { createWalletClient, createPublicClient, http, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { agentRegistryAbi, somniaTestnet, encodeCapabilityAsDataUri } from "@mosaic/sdk";

async function main() {
    const rpc = process.env.SOMNIA_RPC_URL!;
    const registry = process.env.AGENT_REGISTRY_ADDRESS as Address;
    const pk = process.env.AGENT_PRIVATE_KEY as Hex;
    const agentId = BigInt(process.env.GUARDIAN_AGENT_ID ?? "1");

    if (!registry || !pk) {
        throw new Error("missing AGENT_REGISTRY_ADDRESS or AGENT_PRIVATE_KEY");
    }

    const account = privateKeyToAccount(pk);
    const publicClient = createPublicClient({ chain: somniaTestnet, transport: http(rpc) });
    const walletClient = createWalletClient({
        account,
        chain: somniaTestnet,
        transport: http(rpc)
    });

    const before = (await publicClient.readContract({
        address: registry,
        abi: agentRegistryAbi,
        functionName: "getAgent",
        args: [agentId]
    })) as {
        owner: Address;
        pricePerInvocation: bigint;
        metadataURI: string;
        capabilityTag: string;
        active: boolean;
    };

    console.log("current owner:        ", before.owner);
    console.log("current price:        ", before.pricePerInvocation.toString());
    console.log("current capability:   ", before.capabilityTag);
    console.log("current active:       ", before.active);
    console.log("current metadataURI:  ", before.metadataURI.slice(0, 80) + "…");

    if (before.owner.toLowerCase() !== account.address.toLowerCase()) {
        throw new Error(
            `signer ${account.address} is not the agent owner ${before.owner} — cannot update`
        );
    }

    const schema = {
        name: "ProtocolGuardian",
        kind: "security",
        version: "1.0.0",
        description:
            "Mosaic's flagship security agent. Scans a deployed contract for risky opcodes (SELFDESTRUCT, DELEGATECALL) and combines on-chain heuristics with an off-chain runner's structured assessment.",
        methods: [
            {
                name: "scan",
                description: "Returns abi.encode(uint8 score, bytes details) for the target contract",
                args: [{ name: "target", type: "address" }],
                returns: [
                    { name: "score", type: "uint8" },
                    { name: "details", type: "bytes" }
                ]
            }
        ]
    };
    const newMetadataURI = encodeCapabilityAsDataUri(schema);

    console.log("\nposting AgentRegistry.update(agentId, price, newMetadataURI, active)…");
    const hash = await walletClient.writeContract({
        address: registry,
        abi: agentRegistryAbi,
        functionName: "update",
        args: [agentId, before.pricePerInvocation, newMetadataURI, before.active]
    });
    console.log("  tx:", hash);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log("  status:", receipt.status);
    console.log("\n✓ Guardian metadata refreshed. Reload the marketplace page to see it.");
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
TS

echo "✓ wrote $REPO/agents/src/updateGuardianMetadata.ts"
cat <<EOF

Run it now to fix the live Guardian card:
  cd $REPO/agents
  npx tsx --env-file=.env src/updateGuardianMetadata.ts

Then reload mosaic-somnia.vercel.app and the Guardian card should show:
  "Mosaic's flagship security agent. Scans a deployed contract for risky opcodes …"
EOF
