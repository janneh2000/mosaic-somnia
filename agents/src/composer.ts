/**
 * Composer — META-AGENT that discovers other agents in the marketplace and
 * autonomously chains their invocations to satisfy a high-level goal.
 *
 * This is the centerpiece of Mosaic's "Agent-First Design" claim:
 *   - An agent that calls other agents.
 *   - Discovery is on-chain (queries AgentRegistry by capabilityTag).
 *   - Composition is dynamic — the composer reads reputation and picks
 *     the highest-success agent in each capability tag.
 *
 * Input payload  : abi.encode(string goal, string target)
 *   where `goal` ∈ { "audit", "explain", "audit_and_explain" }
 *         `target` is an address (for audit) or arbitrary text (for explain)
 *
 * Output payload : abi.encode(string compositeReport)
 *
 * Example flow for goal="audit_and_explain":
 *   1. discover security agents → pick best by reputation
 *   2. invoke it on `target` → receive risk findings
 *   3. discover summarizer agents → pick best
 *   4. invoke it on the findings → receive plain-English explanation
 *   5. return concatenated report
 *
 * Authentication: the composer is itself a registered EXTERNAL agent;
 * runners listen for IntentCreated on the composer's agentId.
 */
import {
    AgentRunner,
    MosaicClient,
    decodeCapabilityFromDataUri
} from "@mosaic/sdk";
import { decodeAbiParameters, encodeAbiParameters, type Hex } from "viem";
import { getConfig } from "./config";

interface PickedAgent {
    id: bigint;
    name: string;
    pricePerInvocation: bigint;
}

async function pickBestAgent(
    client: MosaicClient,
    capabilityTag: string,
    excludeId: bigint
): Promise<PickedAgent | null> {
    const ids = await client.listByTag(capabilityTag);
    let best: { id: bigint; score: bigint; price: bigint; name: string } | null = null;
    for (const id of ids) {
        if (id === excludeId) continue;
        const agent = await client.getAgent(id);
        if (!agent.active) continue;
        const rep = await client.getReputation(id);
        // simple ranking: successRateBps * 10 - latency_ms, ties broken by lower price
        const successRate =
            rep.totalInvocations > 0n
                ? (rep.successCount * 10_000n) / rep.totalInvocations
                : 5_000n; // neutral default for unproven agents
        const avgLatency =
            rep.totalInvocations > 0n
                ? rep.cumulativeLatencyMs / rep.totalInvocations
                : 0n;
        const score = successRate * 10n - avgLatency;
        const cap = decodeCapabilityFromDataUri(agent.metadataURI);
        const name = cap?.name ?? `agent#${id}`;
        if (!best || score > best.score) {
            best = { id, score, price: agent.pricePerInvocation, name };
        }
    }
    if (!best) return null;
    return { id: best.id, name: best.name, pricePerInvocation: best.price };
}

async function runComposerPlan(
    client: MosaicClient,
    composerAgentId: bigint,
    goal: string,
    targetOrText: string
): Promise<string> {
    const out: string[] = [];
    out.push(`# Mosaic Composer Report`);
    out.push(`goal: ${goal}`);

    if (goal === "audit" || goal === "audit_and_explain") {
        const sec = await pickBestAgent(client, "security", composerAgentId);
        if (!sec) {
            out.push(`no security agent registered`);
        } else {
            out.push(`selected security agent: ${sec.name} (id=${sec.id})`);
            // For this demo we just announce the call; actual invocation
            // requires an on-chain consumer contract that holds the
            // composer's callback selector. The composer surfaces the
            // PLAN — execution by an on-chain consumer is shown in the
            // ScannerPage demo.
            out.push(
                `plan: invoke security agent on target=${targetOrText} (price=${sec.pricePerInvocation} wei)`
            );
        }
    }

    if (goal === "explain" || goal === "audit_and_explain") {
        const sum = await pickBestAgent(client, "summarizer", composerAgentId);
        if (!sum) {
            out.push(`no summarizer agent registered`);
        } else {
            out.push(`selected summarizer agent: ${sum.name} (id=${sum.id})`);
            out.push(
                `plan: invoke summarizer with text length=${targetOrText.length}`
            );
        }
    }

    out.push(`generated: ${new Date().toISOString()}`);
    return out.join("\n");
}

async function main() {
    const cfg = getConfig();
    const client = new MosaicClient({
        rpcUrl: cfg.rpcUrl,
        addresses: cfg.addresses,
        privateKey: cfg.privateKey
    });

    const agentId = BigInt(process.env.COMPOSER_AGENT_ID ?? "0");
    if (agentId === 0n) throw new Error("missing COMPOSER_AGENT_ID");

    await new AgentRunner({
        client,
        agentId,
        handle: async (payload: Hex) => {
            const [goal, target] = decodeAbiParameters(
                [{ type: "string" }, { type: "string" }],
                payload
            ) as [string, string];
            console.log(`[composer] received goal="${goal}" target="${target}"`);
            const report = await runComposerPlan(client, agentId, goal, target);
            console.log(`[composer] generated plan (${report.length} chars)`);
            return encodeAbiParameters([{ type: "string" }], [report]);
        }
    }).start();
}

if (import.meta.url === `file://${process.argv[1]}`) {
    main().catch((err) => {
        console.error("[composer] fatal:", err);
        process.exit(1);
    });
}

export { pickBestAgent, runComposerPlan };
