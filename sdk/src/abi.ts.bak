// Hand-curated ABIs for the Mosaic contracts. Keeping these inline (rather
// than reading from forge artifacts) lets the SDK ship without a Solidity
// toolchain in its dependency graph.

export const agentRegistryAbi = [
    {
        type: "function",
        name: "register",
        stateMutability: "nonpayable",
        inputs: [
            { name: "agentType", type: "uint8" },
            { name: "nativeAgentId", type: "uint256" },
            { name: "pricePerInvocation", type: "uint256" },
            { name: "metadataURI", type: "string" },
            { name: "capabilityTag", type: "string" }
        ],
        outputs: [{ name: "agentId", type: "uint256" }]
    },
    {
        type: "function",
        name: "getAgent",
        stateMutability: "view",
        inputs: [{ name: "agentId", type: "uint256" }],
        outputs: [
            {
                type: "tuple",
                components: [
                    { name: "owner", type: "address" },
                    { name: "agentType", type: "uint8" },
                    { name: "nativeAgentId", type: "uint256" },
                    { name: "pricePerInvocation", type: "uint256" },
                    { name: "metadataURI", type: "string" },
                    { name: "capabilityTag", type: "string" },
                    { name: "active", type: "bool" },
                    { name: "registeredAt", type: "uint64" }
                ]
            }
        ]
    },
    {
        type: "function",
        name: "agentsByTag",
        stateMutability: "view",
        inputs: [{ name: "tag", type: "string" }],
        outputs: [{ type: "uint256[]" }]
    },
    {
        type: "function",
        name: "agentsByOwner",
        stateMutability: "view",
        inputs: [{ name: "owner", type: "address" }],
        outputs: [{ type: "uint256[]" }]
    },
    {
        type: "function",
        name: "nextAgentId",
        stateMutability: "view",
        inputs: [],
        outputs: [{ type: "uint256" }]
    },
    {
        type: "event",
        name: "AgentRegistered",
        inputs: [
            { name: "agentId", type: "uint256", indexed: true },
            { name: "owner", type: "address", indexed: true },
            { name: "agentType", type: "uint8", indexed: false },
            { name: "nativeAgentId", type: "uint256", indexed: false },
            { name: "pricePerInvocation", type: "uint256", indexed: false },
            { name: "capabilityTag", type: "string", indexed: false },
            { name: "metadataURI", type: "string", indexed: false }
        ]
    }
] as const;

export const mosaicHubAbi = [
    {
        type: "function",
        name: "invoke",
        stateMutability: "payable",
        inputs: [
            { name: "agentId", type: "uint256" },
            { name: "payload", type: "bytes" },
            { name: "callbackContract", type: "address" },
            { name: "callbackSelector", type: "bytes4" }
        ],
        outputs: [{ name: "invocationId", type: "uint256" }]
    },
    {
        type: "function",
        name: "fulfillIntent",
        stateMutability: "nonpayable",
        inputs: [
            { name: "invocationId", type: "uint256" },
            { name: "result", type: "bytes" },
            { name: "signature", type: "bytes" }
        ],
        outputs: []
    },
    {
        type: "function",
        name: "refundExpired",
        stateMutability: "nonpayable",
        inputs: [{ name: "invocationId", type: "uint256" }],
        outputs: []
    },
    {
        type: "function",
        name: "invocations",
        stateMutability: "view",
        inputs: [{ name: "id", type: "uint256" }],
        outputs: [
            { name: "agentId", type: "uint256" },
            { name: "caller", type: "address" },
            { name: "callbackContract", type: "address" },
            { name: "callbackSelector", type: "bytes4" },
            { name: "feeEscrowed", type: "uint256" },
            { name: "createdAt", type: "uint128" },
            { name: "status", type: "uint8" },
            { name: "somniaRequestId", type: "uint256" }
        ]
    },
    {
        type: "function",
        name: "withdraw",
        stateMutability: "nonpayable",
        inputs: [],
        outputs: []
    },
    {
        type: "function",
        name: "withdrawable",
        stateMutability: "view",
        inputs: [{ name: "who", type: "address" }],
        outputs: [{ type: "uint256" }]
    },
    {
        type: "event",
        name: "IntentCreated",
        inputs: [
            { name: "invocationId", type: "uint256", indexed: true },
            { name: "agentId", type: "uint256", indexed: true },
            { name: "caller", type: "address", indexed: true },
            { name: "payload", type: "bytes", indexed: false },
            { name: "fee", type: "uint256", indexed: false },
            { name: "nonce", type: "uint256", indexed: false }
        ]
    },
    {
        type: "event",
        name: "NativeRequestForwarded",
        inputs: [
            { name: "invocationId", type: "uint256", indexed: true },
            { name: "agentId", type: "uint256", indexed: true },
            { name: "somniaRequestId", type: "uint256", indexed: false },
            { name: "deposit", type: "uint256", indexed: false }
        ]
    },
    {
        type: "event",
        name: "InvocationFulfilled",
        inputs: [
            { name: "invocationId", type: "uint256", indexed: true },
            { name: "agentId", type: "uint256", indexed: true },
            { name: "status", type: "uint8", indexed: false },
            { name: "latencyMs", type: "uint128", indexed: false }
        ]
    }
] as const;

export const reputationLedgerAbi = [
    {
        type: "function",
        name: "getStats",
        stateMutability: "view",
        inputs: [{ name: "agentId", type: "uint256" }],
        outputs: [
            {
                type: "tuple",
                components: [
                    { name: "totalInvocations", type: "uint64" },
                    { name: "successCount", type: "uint64" },
                    { name: "failureCount", type: "uint64" },
                    { name: "timeoutCount", type: "uint64" },
                    { name: "cumulativeLatencyMs", type: "uint128" },
                    { name: "lastUpdatedAt", type: "uint128" }
                ]
            }
        ]
    },
    {
        type: "function",
        name: "successRateBps",
        stateMutability: "view",
        inputs: [{ name: "agentId", type: "uint256" }],
        outputs: [{ type: "uint256" }]
    }
] as const;

export const guardianAbi = [
    {
        type: "function",
        name: "requestScan",
        stateMutability: "payable",
        inputs: [{ name: "target", type: "address" }],
        outputs: [{ name: "invocationId", type: "uint256" }]
    },
    {
        type: "function",
        name: "lastReport",
        stateMutability: "view",
        inputs: [{ name: "target", type: "address" }],
        outputs: [
            { name: "target", type: "address" },
            { name: "codeSize", type: "uint256" },
            { name: "hasSelfdestruct", type: "bool" },
            { name: "hasDelegatecall", type: "bool" },
            { name: "onchainRiskScore", type: "uint8" },
            { name: "offchainRiskScore", type: "uint8" },
            { name: "compositeRiskScore", type: "uint8" },
            { name: "generatedAt", type: "uint256" },
            { name: "offchainDetails", type: "bytes" }
        ]
    },
    {
        type: "function",
        name: "guardianAgentId",
        stateMutability: "view",
        inputs: [],
        outputs: [{ type: "uint256" }]
    },
    {
        type: "event",
        name: "ScanCompleted",
        inputs: [
            { name: "target", type: "address", indexed: true },
            { name: "composite", type: "uint8", indexed: false },
            {
                name: "report",
                type: "tuple",
                indexed: false,
                components: [
                    { name: "target", type: "address" },
                    { name: "codeSize", type: "uint256" },
                    { name: "hasSelfdestruct", type: "bool" },
                    { name: "hasDelegatecall", type: "bool" },
                    { name: "onchainRiskScore", type: "uint8" },
                    { name: "offchainRiskScore", type: "uint8" },
                    { name: "compositeRiskScore", type: "uint8" },
                    { name: "generatedAt", type: "uint256" },
                    { name: "offchainDetails", type: "bytes" }
                ]
            }
        ]
    }
] as const;
