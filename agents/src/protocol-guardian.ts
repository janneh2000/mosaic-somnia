/**
 * Protocol Guardian — flagship security agent for the Mosaic marketplace.
 *
 * Responsibilities:
 *   1. Listen for IntentCreated events on the Guardian agent.
 *   2. For each scan request (payload = abi.encode(address target)) fetch
 *      the target's bytecode and emit a structured risk assessment.
 *   3. Return abi.encode(uint8 score, bytes details) to the on-chain
 *      GuardianModule, which combines it with on-chain heuristics.
 *
 * The risk assessment uses **explainable heuristics only** — no opaque
 * model calls. Reasoning: we want every assertion to be defensible to
 * judges and reproducible on-chain.
 */
import { AgentRunner, MosaicClient } from "@mosaic/sdk";
import {
    decodeAbiParameters,
    encodeAbiParameters,
    getAddress,
    type Address,
    type Hex
} from "viem";
import { getConfig } from "./config";

const SUSPICIOUS_OPCODES: Record<number, string> = {
    0xff: "SELFDESTRUCT",
    0xf4: "DELEGATECALL",
    0xf5: "CREATE2",
    0xfa: "STATICCALL"
};

interface RiskFinding {
    severity: "low" | "medium" | "high";
    code: string;
    detail: string;
}

interface RiskAssessment {
    score: number; // 0..100
    findings: RiskFinding[];
    sizeBytes: number;
    inspectedAt: string;
}

async function assessTarget(client: MosaicClient, target: Address): Promise<RiskAssessment> {
    const code = await client.publicClient.getBytecode({ address: target });
    if (!code || code === "0x") {
        return {
            score: 95,
            sizeBytes: 0,
            findings: [
                {
                    severity: "high",
                    code: "NO_CODE",
                    detail: "Target has no on-chain bytecode (EOA, self-destructed, or wrong address)"
                }
            ],
            inspectedAt: new Date().toISOString()
        };
    }

    // strip 0x
    const bytes = Buffer.from(code.slice(2), "hex");
    const findings: RiskFinding[] = [];
    let score = 5; // base risk for any contract

    const seen = new Set<number>();
    for (let i = 0; i < bytes.length; i++) {
        const op = bytes[i]!;
        // PUSH1..PUSH32 skip their immediate data so we don't see literal bytes as opcodes
        if (op >= 0x60 && op <= 0x7f) {
            i += op - 0x5f;
            continue;
        }
        if (SUSPICIOUS_OPCODES[op]) {
            if (!seen.has(op)) {
                seen.add(op);
                if (op === 0xff) {
                    score += 40;
                    findings.push({
                        severity: "high",
                        code: "SELFDESTRUCT",
                        detail: "Contract can be irreversibly destroyed; funds may be locked or seized"
                    });
                } else if (op === 0xf4) {
                    score += 25;
                    findings.push({
                        severity: "medium",
                        code: "DELEGATECALL",
                        detail: "Delegatecall present — upgrade/proxy logic; verify caller controls"
                    });
                } else if (op === 0xf5) {
                    score += 10;
                    findings.push({
                        severity: "low",
                        code: "CREATE2",
                        detail: "Uses CREATE2 — supports deterministic factory deployments"
                    });
                }
            }
        }
    }

    if (bytes.length < 200) {
        score += 10;
        findings.push({
            severity: "low",
            code: "TINY_CODE",
            detail: `Code is only ${bytes.length} bytes — likely a minimal proxy or stub`
        });
    } else if (bytes.length > 24_000) {
        // 24KB EIP-170 limit; above that on Somnia is unusual
        score += 5;
        findings.push({
            severity: "low",
            code: "JUMBO_CODE",
            detail: `Code is ${bytes.length} bytes — large surface area`
        });
    }

    score = Math.min(100, score);
    return {
        score,
        sizeBytes: bytes.length,
        findings,
        inspectedAt: new Date().toISOString()
    };
}

function encodeGuardianResult(assessment: RiskAssessment): Hex {
    const detailsJson = JSON.stringify(assessment);
    const detailsHex = ("0x" + Buffer.from(detailsJson, "utf8").toString("hex")) as Hex;
    return encodeAbiParameters(
        [{ type: "uint8" }, { type: "bytes" }],
        [assessment.score, detailsHex]
    );
}

async function main() {
    const cfg = getConfig();
    const client = new MosaicClient({
        rpcUrl: cfg.rpcUrl,
        addresses: cfg.addresses,
        privateKey: cfg.privateKey
    });

    const guardianAgentId = BigInt(process.env.GUARDIAN_AGENT_ID ?? "0");
    if (guardianAgentId === 0n) {
        throw new Error("missing GUARDIAN_AGENT_ID env var (printed by deploy script)");
    }

    const runner = new AgentRunner({
        client,
        agentId: guardianAgentId,
        pollIntervalMs: 2_000,
        handle: async (payload, ctx) => {
            // GuardianModule encodes payload as abi.encode(address target)
            const [target] = decodeAbiParameters(
                [{ type: "address" }],
                payload
            ) as [Address];
            const norm = getAddress(target);
            console.log(`[guardian] scanning ${norm} for invocation=${ctx.invocationId}`);
            const assessment = await assessTarget(client, norm);
            console.log(
                `[guardian] target=${norm} score=${assessment.score} findings=${assessment.findings.length}`
            );
            return encodeGuardianResult(assessment);
        }
    });

    await runner.start();
}

if (import.meta.url === `file://${process.argv[1]}`) {
    main().catch((err) => {
        console.error("[guardian] fatal:", err);
        process.exit(1);
    });
}

// utility re-exports for tests
export { assessTarget, encodeGuardianResult };
