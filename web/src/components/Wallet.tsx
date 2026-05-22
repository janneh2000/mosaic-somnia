"use client";
import { useAccount, useConnect, useDisconnect, useChainId } from "wagmi";
import { somniaTestnet } from "@mosaic/sdk";
import { ensureSomniaChain } from "@/lib/ensureChain";

export function Wallet() {
    const { address, isConnected } = useAccount();
    const { connect, connectors, isPending } = useConnect();
    const { disconnect } = useDisconnect();
    const chainId = useChainId();
    const wrongChain = isConnected && chainId !== somniaTestnet.id;

    if (!isConnected) {
        return (
            <button
                className="btn"
                disabled={isPending}
                onClick={() => connect({ connector: connectors[0]! })}
            >
                {isPending ? "Connecting…" : "Connect Wallet"}
            </button>
        );
    }
    if (wrongChain) {
        return (
            <button
                className="btn"
                onClick={() =>
                    ensureSomniaChain().catch((err) => {
                        console.error("[wallet] switch failed:", err);
                        alert(
                            "Switch failed — open your wallet and switch to Somnia Testnet manually."
                        );
                    })
                }
            >
                Switch to Somnia Testnet
            </button>
        );
    }
    return (
        <div className="flex gap-3 items-center">
            <span className="badge">
                {address?.slice(0, 6)}…{address?.slice(-4)}
            </span>
            <button className="btn" onClick={() => disconnect()}>
                Disconnect
            </button>
        </div>
    );
}
