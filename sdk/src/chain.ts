import { defineChain } from "viem";

/**
 * Somnia Shannon Testnet — chain ID 50312.
 * Source: https://docs.somnia.network/developer/network-info
 */
export const somniaTestnet = defineChain({
    id: 50_312,
    name: "Somnia Testnet (Shannon)",
    nativeCurrency: { name: "Somnia Test Token", symbol: "STT", decimals: 18 },
    rpcUrls: {
        default: {
            http: ["https://api.infra.testnet.somnia.network/"],
            webSocket: ["wss://api.infra.testnet.somnia.network/ws"]
        }
    },
    blockExplorers: {
        default: {
            name: "Shannon Explorer",
            url: "https://shannon-explorer.somnia.network"
        }
    },
    testnet: true
});

export const somniaMainnet = defineChain({
    id: 5_031,
    name: "Somnia Mainnet",
    nativeCurrency: { name: "Somnia", symbol: "SOMI", decimals: 18 },
    rpcUrls: {
        default: {
            http: ["https://api.infra.mainnet.somnia.network/"],
            webSocket: ["wss://api.infra.mainnet.somnia.network/ws"]
        }
    },
    blockExplorers: {
        default: { name: "Somnia Explorer", url: "https://explorer.somnia.network" }
    }
});

/** Official SomniaAgents platform addresses (Solidity-callable). */
export const SOMNIA_AGENTS_ADDRESS = {
    testnet: "0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776",
    mainnet: "0x5E5205CF39E766118C01636bED000A54D93163E6"
} as const;
