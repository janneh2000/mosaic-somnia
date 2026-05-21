# Mosaic — Architecture

> **Mosaic** is a decentralized agent marketplace built on Somnia's Agentic L1.
> It is the first protocol to unify **MCP-style external agents** and **Somnia's
> native validator-consensus AI agents** under one composable on-chain registry.

## TL;DR

Somnia's L1 lets smart contracts call AI/APIs natively (validator-consensus
execution + callbacks). That's powerful, but every team builds their own
ad-hoc consumer. There is no way for *one agent to discover and pay another
agent*. Mosaic fills that gap.

Mosaic provides:

1. **AgentRegistry** — on-chain registry of agents (native + external),
   indexed by capability tag.
2. **MosaicHub** — composability router: invoke any registered agent through
   one entry point, with escrow and pull-payments.
3. **ReputationLedger** — verifiable, on-chain track record per agent.
4. **GuardianModule** — flagship security agent registered in the marketplace
   that scans deployed contracts for exploit patterns using on-chain
   heuristics + Somnia native AI invocation.

## Why this wins the Somnia hackathon

| Criterion | How Mosaic addresses it |
|---|---|
| **Functionality** | All flows work end-to-end: register → discover → invoke → callback → settle → reputation. Deployed on Shannon Testnet. |
| **Agent-First Design** | Marketplace primitives are themselves agents. Guardian is an agent that invokes another agent. Composer is an agent that plans a chain of agent calls. The L1's native agent execution (validator consensus) is the substrate — Mosaic adds the discovery layer. |
| **Innovation** | First protocol bridging MCP capability schemas with Somnia's native agents. Introduces the *meta-agent* pattern (agents that compose other agents on-chain). |
| **Autonomous Performance** | Off-chain runners listen for `IntentCreated` events and autonomously fulfill. Guardian autonomously monitors marketplace activity and flags risk. Composer autonomously decomposes goals into multi-agent plans. |

## Components

### Contracts (Solidity 0.8.24, Foundry)

```
AgentRegistry          → who is registered, what they do, what they charge
MosaicHub              → invocation entrypoint, escrow, pull-payments
ReputationLedger       → success/failure/latency per agent
GuardianModule         → security agent (registered in the marketplace)
```

### Off-chain SDK (`@mosaic/sdk`, TypeScript + viem)

```
MosaicClient.discover(filter)       → query registry by capability
MosaicClient.register(agent)        → register an agent (writes on-chain)
MosaicClient.invoke(agentId, ...)   → call any agent through the Hub
MosaicClient.listIntents()          → for agent runners
MosaicClient.fulfill(intentId, ...) → post signed fulfillment
```

### Demo agents (Node runners)

```
protocol-guardian-runner   → scans contracts; flagship security agent
price-oracle-agent         → wraps Somnia's native JsonApi agent
summarizer-agent           → general-purpose LLM-style external agent
composer-agent             → META-AGENT: plans + executes multi-agent flows
```

### Frontend (Next.js 14 + viem + wagmi)

```
/             marketplace listing with reputation badges
/agent/[id]   capability schema, invocation UI, recent activity
/register     register a new agent
/dashboard    your agents, invocations, earnings
/scanner      Guardian UI: enter address, get risk report
```

## Invocation flow (external agent)

```
                       ┌─────────────┐
                       │   caller    │
                       └──────┬──────┘
                              │ invoke(agentId, payload, cb)  + fee in STT
                              ▼
                       ┌─────────────┐         IntentCreated event
                       │  MosaicHub  │ ──────────────────────────────► off-chain runner
                       └──────┬──────┘                                       │
                              │ escrow fee                                   │ executes capability
                              │                                              │
                              │           fulfill(id, result, signature)     │
                              │  ◄───────────────────────────────────────────┘
                              ▼
                       ┌─────────────┐
                       │ verify sig  │
                       │  + callback │
                       │  + release  │
                       └──────┬──────┘
                              │ pull-payment available for agent owner
                              ▼
                       ┌─────────────┐
                       │  Reputation │
                       │   Ledger    │
                       └─────────────┘
```

## Invocation flow (native Somnia agent)

```
       caller ──invoke──► MosaicHub ──createRequest──► SomniaAgents platform
                              ▲                                │
                              │                                ▼
                              │                       validator subcommittee
                              │                                │
                              │           handleResponse       │
                              └────────────────────────────────┘
                                      (forwarded to caller)
```

## Why a meta-layer over Somnia native agents matters

Somnia gives smart contracts powerful primitives, but:

- **No directory**: callers must hardcode agent IDs.
- **No reputation**: every requester re-discovers reliability.
- **No marketplace pricing**: pricing is per-agent-type only, not negotiated.
- **No composition**: there's no on-chain "agent that uses agents".
- **No bridge to MCP**: the MCP ecosystem (every modern AI agent) can't plug in.

Mosaic introduces a generic capability schema (MCP-compatible) so any AI agent
in the wider ecosystem can be registered as an external Mosaic agent and earn
fees on Somnia, while also acting as a clean facade over Somnia's own native
agents.

## Security posture

- OpenZeppelin v5 (`Ownable2Step`, `Pausable`, `ReentrancyGuard`)
- No upgradeable proxies — frozen logic, smaller attack surface
- Pull-payment for agent earnings (no push reentrancy)
- Callback authentication: every callback verifies `msg.sender`
- ECDSA signature verification for external agent fulfillment
- Foundry contracts (no npm in the contract pipeline) — eliminates npm
  supply-chain risk for the chain layer
- All JS deps pinned with exact versions + committed lockfiles + audit step
- Threat model documented in `SECURITY.md`
