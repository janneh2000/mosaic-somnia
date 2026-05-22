"use client";

import { somniaTestnet } from "@mosaic/sdk";

/**
 * Direct-to-provider chain switcher. Bypasses wagmi entirely because some
 * wallets (notably Phantom EVM and any provider that proxies window.ethereum
 * from another extension) don't reliably report a successful chain switch
 * back to wagmi via the eth_chainId event, leaving wagmi's `useChainId` stuck
 * on the old value and triggering a false-positive chain-mismatch error.
 *
 * Returns the chainId reported by the wallet after the switch (as a number).
 */
export async function ensureSomniaChain(): Promise<number> {
    const eth = (
        globalThis as unknown as {
            ethereum?: {
                request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
            };
        }
    ).ethereum;
    if (!eth) {
        throw new Error("No injected wallet provider found.");
    }

    const targetHex = "0x" + somniaTestnet.id.toString(16); // 50312 -> 0xc488

    try {
        const current = (await eth.request({ method: "eth_chainId" })) as string;
        if (current && parseInt(current, 16) === somniaTestnet.id) {
            return somniaTestnet.id;
        }
    } catch {
        /* fall through to the switch attempt */
    }

    try {
        await eth.request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: targetHex }]
        });
    } catch (err) {
        const code = (err as { code?: number }).code;
        if (code === 4902 || code === -32603) {
            await eth.request({
                method: "wallet_addEthereumChain",
                params: [
                    {
                        chainId: targetHex,
                        chainName: "Somnia Testnet",
                        nativeCurrency: {
                            name: "Somnia Test Token",
                            symbol: "STT",
                            decimals: 18
                        },
                        rpcUrls: ["https://api.infra.testnet.somnia.network/"],
                        blockExplorerUrls: ["https://shannon-explorer.somnia.network"]
                    }
                ]
            });
            await eth.request({
                method: "wallet_switchEthereumChain",
                params: [{ chainId: targetHex }]
            });
        } else {
            throw err;
        }
    }

    const after = (await eth.request({ method: "eth_chainId" })) as string;
    return parseInt(after, 16);
}
