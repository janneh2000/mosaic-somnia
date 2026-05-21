"use client";
import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { somniaTestnet } from "@mosaic/sdk";

export function Wallet() {
    const { address, isConnected } = useAccount();
    const { connect, connectors, isPending } = useConnect();
    const { disconnect } = useDisconnect();
    const chainId = useChainId();
    const { switchChain } = useSwitchChain();
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
            <button className="btn" onClick={() => switchChain({ chainId: somniaTestnet.id })}>
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
