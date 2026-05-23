import { createPublicClient, http, type Address } from "viem";
import { agentRegistryAbi, somniaTestnet } from "@mosaic/sdk";

async function main() {
    const client = createPublicClient({
        chain: somniaTestnet,
        transport: http(process.env.SOMNIA_RPC_URL!)
    });

    const agentId = BigInt(process.env.GUARDIAN_AGENT_ID ?? "1");
    const agent = (await client.readContract({
        address: process.env.AGENT_REGISTRY_ADDRESS as Address,
        abi: agentRegistryAbi,
        functionName: "getAgent",
        args: [agentId]
    })) as { owner: Address; capabilityTag: string; active: boolean };

    console.log("\n--- Guardian ownership check ---");
    console.log("agent id queried:        ", agentId.toString());
    console.log("on-chain owner:          ", agent.owner);
    console.log("on-chain capability tag: ", agent.capabilityTag);
    console.log("on-chain active:         ", agent.active);
    console.log();
    console.log("Compare 'on-chain owner' above against the wallet whose key");
    console.log("you put into AGENT_PRIVATE_KEY in agents/.env. They MUST match");
    console.log("for fulfillIntent to succeed.");
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
