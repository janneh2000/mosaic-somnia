import type { Address } from "viem";

export const config = {
    addresses: {
        agentRegistry: (process.env.NEXT_PUBLIC_AGENT_REGISTRY ?? "0x0000000000000000000000000000000000000000") as Address,
        mosaicHub: (process.env.NEXT_PUBLIC_MOSAIC_HUB ?? "0x0000000000000000000000000000000000000000") as Address,
        reputationLedger: (process.env.NEXT_PUBLIC_REPUTATION_LEDGER ?? "0x0000000000000000000000000000000000000000") as Address,
        guardianModule: (process.env.NEXT_PUBLIC_GUARDIAN_MODULE ?? "0x0000000000000000000000000000000000000000") as Address
    },
    rpcUrl: process.env.NEXT_PUBLIC_SOMNIA_RPC ?? "https://api.infra.testnet.somnia.network/"
};
