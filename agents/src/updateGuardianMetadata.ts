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

    // The SDK's curated agentRegistryAbi doesn't include update() (no
    // production codepath calls it). Inline a one-function fragment.
    const updateAbi = [
        {
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
        }
    ] as const;

    console.log("\nposting AgentRegistry.update(agentId, price, newMetadataURI, active)…");
    const hash = await walletClient.writeContract({
        address: registry,
        abi: updateAbi,
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
