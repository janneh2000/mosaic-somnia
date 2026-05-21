/**
 * Summarizer agent — demonstrates how a generic MCP-style LLM agent plugs
 * into the Mosaic marketplace.
 *
 * Payload: abi.encode(string text)
 * Result:  abi.encode(string summary)
 *
 * The summarization logic here is intentionally local (rule-based) so the
 * demo runs without an external API key. Swap in an LLM call in production.
 */
import { AgentRunner, MosaicClient } from "@mosaic/sdk";
import { decodeAbiParameters, encodeAbiParameters, type Hex } from "viem";
import { getConfig } from "./config";

function summarize(text: string, maxSentences = 3): string {
    const cleaned = text.replace(/\s+/g, " ").trim();
    const sentences = cleaned
        .split(/(?<=[.!?])\s+/)
        .filter((s) => s.length > 0);
    if (sentences.length <= maxSentences) return cleaned;

    // simple extractive heuristic: rank sentences by length-normalized
    // information density (rare-word count / sentence length).
    const wordFreq = new Map<string, number>();
    for (const s of sentences) {
        for (const w of s.toLowerCase().split(/\W+/)) {
            if (w.length < 3) continue;
            wordFreq.set(w, (wordFreq.get(w) ?? 0) + 1);
        }
    }
    const scored = sentences.map((s, idx) => {
        const ws = s.toLowerCase().split(/\W+/).filter((w) => w.length >= 3);
        if (ws.length === 0) return { idx, score: 0 };
        const rareWords = ws.filter((w) => (wordFreq.get(w) ?? 0) <= 2).length;
        return { idx, score: rareWords / ws.length };
    });
    scored.sort((a, b) => b.score - a.score);
    const picks = new Set(scored.slice(0, maxSentences).map((x) => x.idx));
    return sentences
        .map((s, i) => (picks.has(i) ? s : null))
        .filter((s): s is string => s !== null)
        .join(" ");
}

async function main() {
    const cfg = getConfig();
    const client = new MosaicClient({
        rpcUrl: cfg.rpcUrl,
        addresses: cfg.addresses,
        privateKey: cfg.privateKey
    });

    const agentId = BigInt(process.env.SUMMARIZER_AGENT_ID ?? "0");
    if (agentId === 0n) throw new Error("missing SUMMARIZER_AGENT_ID");

    await new AgentRunner({
        client,
        agentId,
        handle: async (payload: Hex) => {
            const [text] = decodeAbiParameters(
                [{ type: "string" }],
                payload
            ) as [string];
            const summary = summarize(text);
            console.log(`[summarizer] in=${text.length} chars out=${summary.length} chars`);
            return encodeAbiParameters([{ type: "string" }], [summary]);
        }
    }).start();
}

// Only run the runner when invoked as a script (not when imported by tests).
if (import.meta.url === `file://${process.argv[1]}`) {
    main().catch((err) => {
        console.error("[summarizer] fatal:", err);
        process.exit(1);
    });
}

export { summarize };
