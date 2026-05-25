import "./globals.css";
import type { Metadata } from "next";
import { Providers } from "./providers";

export const metadata: Metadata = {
    title: "Mosaic — Agent Marketplace on Somnia",
    description:
        "MCP-style agent marketplace on Somnia's Agentic L1: discover, invoke, and compose autonomous agents on-chain."
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
    return (
        <html lang="en">
            <body>
                <Providers>
                    <header className="mx-auto flex max-w-5xl items-center justify-between p-6">
                        <a href="/" className="text-xl font-semibold tracking-tight">
                            <span className="text-emerald-400">Mosaic</span>
                            <span className="ml-2 text-zinc-500">
                                · the agent marketplace on Somnia
                            </span>
                        </a>
                        <nav className="flex gap-4 text-sm text-zinc-300">
                            <a href="/scanner" className="hover:text-emerald-400">
                                Guardian
                            </a>
                            <a href="/register" className="hover:text-emerald-400">
                                Register
                            </a>
                        </nav>
                    </header>
                    <main className="mx-auto max-w-5xl p-6">{children}</main>
                    <footer className="mx-auto max-w-5xl p-6 text-xs text-zinc-500">
                        Built on Somnia Agentic L1 · Chain ID 50312 · Shannon Testnet
                    </footer>
                </Providers>
            </body>
        </html>
    );
}
