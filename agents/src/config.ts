import { type Address, type Hex } from "viem";

function requireEnv(name: string): string {
    const v = process.env[name];
    if (!v) throw new Error(`missing env var: ${name}`);
    return v;
}

export function getConfig() {
    return {
        rpcUrl: process.env.SOMNIA_RPC_URL ?? "https://api.infra.testnet.somnia.network/",
        privateKey: requireEnv("AGENT_PRIVATE_KEY") as Hex,
        addresses: {
            agentRegistry: requireEnv("AGENT_REGISTRY_ADDRESS") as Address,
            mosaicHub: requireEnv("MOSAIC_HUB_ADDRESS") as Address,
            reputationLedger: requireEnv("REPUTATION_LEDGER_ADDRESS") as Address,
            guardianModule: (process.env.GUARDIAN_MODULE_ADDRESS ?? undefined) as
                | Address
                | undefined
        }
    };
}
