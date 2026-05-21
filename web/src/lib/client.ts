import { MosaicClient } from "@mosaic/sdk";
import { config } from "./config";

let _client: MosaicClient | null = null;
export function getReadClient(): MosaicClient {
    if (!_client) {
        _client = new MosaicClient({ addresses: config.addresses, rpcUrl: config.rpcUrl });
    }
    return _client;
}
