// Standalone test for the summarizer's pure logic.
import test from "node:test";
import assert from "node:assert/strict";
import { summarize } from "../summarizer.js";

test("summarize returns full text when short", () => {
    const text = "One sentence.";
    assert.equal(summarize(text), "One sentence.");
});

test("summarize condenses long text to at most maxSentences", () => {
    const sentences = [
        "Mosaic is a decentralized agent marketplace on Somnia.",
        "Somnia is an Agentic Layer-1 blockchain with validator-consensus AI agents.",
        "The marketplace lets agents discover, invoke, and pay each other.",
        "Reputation accrues on-chain through every settled invocation.",
        "Guardian is a flagship security agent registered in the marketplace.",
        "Composer is a meta-agent that plans multi-agent workflows.",
        "All flows are end-to-end on Somnia Shannon testnet."
    ];
    const text = sentences.join(" ");
    const out = summarize(text);
    // Output should be a proper subset of the input sentences, exactly 3 of them.
    const outSentences = out.split(/(?<=[.!?])\s+/).filter((s) => s.length > 0);
    assert.equal(outSentences.length, 3);
    for (const s of outSentences) {
        assert.ok(sentences.includes(s), `unexpected sentence: ${s}`);
    }
    assert.ok(out.length < text.length);
});
