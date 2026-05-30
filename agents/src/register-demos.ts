/**
 * One-shot registration of the demo external agents.
 * Run AFTER deploying the contracts via `forge script script/Deploy.s.sol`.
 *
 * Required env:
 *   AGENT_PRIVATE_KEY               – signer (also becomes agent owner)
 *   AGENT_REGISTRY_ADDRESS          – from deploy logs
 *   MOSAIC_HUB_ADDRESS              – from deploy logs
 *   REPUTATION_LEDGER_ADDRESS       – from deploy logs
 *
 * Prints the agent IDs needed by the runner scripts.
 */
import { AgentType, MosaicClient, encodeCapabilityAsDataUri } from "@mosaic/sdk";
import { parseEther } from "viem";
import { getConfig } from "./config";

const summarizerSchema = {
    name: "MosaicSummarizer",
    kind: "summarizer",
    version: "1.0.0",
    description: "Extractive text summarizer (local heuristic, no LLM dependency).",
    methods: [
        {
            name: "summarize",
            description: "Returns up to 3 high-density sentences from the input text",
            args: [{ name: "text", type: "string" }],
            returns: [{ name: "summary", type: "string" }]
        }
    ]
};

const composerSchema = {
    name: "MosaicComposer",
    kind: "composer",
    version: "1.0.0",
    description:
        "Meta-agent: discovers other agents in the registry by capability tag, ranks by reputation, and executes a multi-agent chain on-chain to satisfy a goal (e.g. audit_and_explain feeds a security agent's findings into a summarizer).",
    methods: [
        {
            name: "plan",
            description: "Goal ∈ {audit, explain, audit_and_explain}; target = address or text",
            args: [
                { name: "goal", type: "string" },
                { name: "target", type: "string" }
            ],
            returns: [{ name: "report", type: "string" }]
        }
    ]
};

async function main() {
    const cfg = getConfig();
    const client = new MosaicClient({
        rpcUrl: cfg.rpcUrl,
        addresses: cfg.addresses,
        privateKey: cfg.privateKey
    });

    console.log("registering summarizer…");
    const summarizerId = await client.register({
        agentType: AgentType.EXTERNAL,
        pricePerInvocation: parseEther("0.01"),
        metadataURI: encodeCapabilityAsDataUri(summarizerSchema),
        capabilityTag: "summarizer"
    });
    console.log(`  ✓ summarizer agentId = ${summarizerId}`);

    console.log("registering composer…");
    const composerId = await client.register({
        agentType: AgentType.EXTERNAL,
        pricePerInvocation: parseEther("0.02"),
        metadataURI: encodeCapabilityAsDataUri(composerSchema),
        capabilityTag: "composer"
    });
    console.log(`  ✓ composer agentId = ${composerId}`);

    console.log("\nexport SUMMARIZER_AGENT_ID=" + summarizerId);
    console.log("export COMPOSER_AGENT_ID=" + composerId);
}

main().catch((err) => {
    console.error("register-demos failed:", err);
    process.exit(1);
});
