"use client";
import { http, createConfig } from "wagmi";
import { injected } from "wagmi/connectors";
import { somniaTestnet } from "@mosaic/sdk";
import { config as appConfig } from "./config";

export const wagmiConfig = createConfig({
    chains: [somniaTestnet],
    connectors: [injected()],
    transports: { [somniaTestnet.id]: http(appConfig.rpcUrl) }
});
