// Standalone, no-network sanity test for the fulfillment digest.
// Run with: node --import tsx --test src/__tests__/digest.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { keccak256, encodeAbiParameters, hashMessage, toBytes } from "viem";
import { MosaicClient } from "../client.js";

test("buildFulfillmentDigest matches MosaicHub's expected hash", () => {
    const hub = "0x1234567890123456789012345678901234567890" as const;
    const invocationId = 42n;
    const result = "0xdeadbeef" as const;

    const expectedInner = keccak256(
        encodeAbiParameters(
            [{ type: "address" }, { type: "uint256" }, { type: "bytes" }],
            [hub, invocationId, result]
        )
    );
    const expected = hashMessage({ raw: toBytes(expectedInner) });

    const actual = MosaicClient.buildFulfillmentDigest(hub, invocationId, result);
    assert.equal(actual, expected);
});

test("buildFulfillmentDigest is sensitive to invocationId", () => {
    const hub = "0x1234567890123456789012345678901234567890" as const;
    const a = MosaicClient.buildFulfillmentDigest(hub, 1n, "0x00");
    const b = MosaicClient.buildFulfillmentDigest(hub, 2n, "0x00");
    assert.notEqual(a, b);
});

test("buildFulfillmentDigest is sensitive to hub address", () => {
    const a = MosaicClient.buildFulfillmentDigest(
        "0x1111111111111111111111111111111111111111",
        1n,
        "0x00"
    );
    const b = MosaicClient.buildFulfillmentDigest(
        "0x2222222222222222222222222222222222222222",
        1n,
        "0x00"
    );
    assert.notEqual(a, b);
});
