# Mosaic

**A decentralized agent marketplace on Somnia's Agentic L1.**

Mosaic is the first protocol to unify **MCP-style external agents** and **Somnia's
native validator-consensus AI agents** under one composable on-chain registry.
Agents discover each other, get paid in STT, accrue verifiable reputation, and
compose into multi-agent workflows — all on Somnia Shannon Testnet (chain ID
50312).

Submission for the [Encode × Somnia Agentathon](https://www.encodeclub.com/my-programmes/agentathon).

---

## What it does

Somnia's L1 lets any smart contract call AI and APIs natively, with
validator-consensus on the output. That is the substrate. **Mosaic adds the
discovery, payment, and composition layer Somnia is missing**:

1. **`AgentRegistry`** — any wallet registers an agent with capability metadata
   (MCP-compatible JSON), a per-invocation price, and a one-word capability tag.
2. **`MosaicHub`** — one entrypoint to invoke *any* registered agent. Routes
   native invocations to Somnia's `SomniaAgents` platform, escrows fees for
   external agents until off-chain runners post a signed result.
3. **`ReputationLedger`** — every invocation is recorded as success / failure /
   timeout with latency. Reputation is the on-chain truth.
4. **`GuardianModule`** — the flagship security agent. Self-registers in the
   marketplace, accepts scan requests against any address, combines an on-chain
   bytecode heuristic with an off-chain risk assessment, and emits a composite
   risk score.

The marketplace ships with three demo agents:

| Agent | Capability | Demonstrates |
|---|---|---|
| **Protocol Guardian** | `security` | Real on-chain heuristic + off-chain assessment with signed fulfillment |
| **Summarizer** | `summarizer` | Generic MCP-style external agent (drop-in for any LLM agent) |
| **Composer** | `composer` | **Meta-agent** that queries the registry, ranks agents by reputation, and plans multi-agent flows |

---

## Why it wins

| Judging criterion | How Mosaic addresses it |
|---|---|
| **Functionality** | All flows work end-to-end: register → discover → invoke → callback → settle → reputation. Deployed on Shannon Testnet. Unit-tested contract suite. Frontend dashboard for live demo. |
| **Agent-First Design** | Marketplace primitives are themselves agents. Guardian is an agent that invokes another agent. Composer is an agent that *plans* a chain of agent calls. The L1's native validator-consensus agent execution is a first-class type in the registry. |
| **Innovation & Technical Creativity** | First protocol bridging MCP capability schemas with Somnia's native agents. Introduces the *meta-agent* pattern (agents that compose other agents on-chain). Generic MCP-compatible capability schema means any agent in the wider ecosystem can plug in. |
| **Autonomous Performance** | Off-chain runners listen for `IntentCreated` events and autonomously fulfill — no orchestrator. Guardian autonomously assesses contracts. Composer autonomously decomposes goals into multi-agent plans. |

---

## Quickstart

```bash
# 1. Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. Install all deps
make setup

# 3. Build + test contracts
make test

# 4. Deploy to Somnia testnet
export DEPLOYER_PK=0x...   # your funded testnet key
make deploy
# Note the printed addresses (AgentRegistry, MosaicHub, ReputationLedger,
# GuardianModule) and guardian agent id.

# 5. Wire up env for runners
export AGENT_PRIVATE_KEY=$DEPLOYER_PK
export AGENT_REGISTRY_ADDRESS=0x...
export MOSAIC_HUB_ADDRESS=0x...
export REPUTATION_LEDGER_ADDRESS=0x...
export GUARDIAN_MODULE_ADDRESS=0x...
export GUARDIAN_AGENT_ID=1     # printed by Deploy.s.sol

# 6. Register demo agents
make register
# Copy the printed SUMMARIZER_AGENT_ID and COMPOSER_AGENT_ID into your env.

# 7. Start runners
make run-agents

# 8. In another shell, start the dashboard
cp web/.env.example web/.env.local
# fill in the four NEXT_PUBLIC_ addresses
make web   # http://localhost:3000
```

### Get testnet STT

The Somnia testnet faucets are at:

- https://testnet.somnia.network/
- https://cloud.google.com/application/web3/faucet/somnia/shannon
- Ask in the [Somnia Discord](https://discord.com/invite/somnia) `#dev-chat`

---

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design and
invocation flows.

```
contracts/        Foundry project (Solidity 0.8.24)
  src/
    AgentRegistry.sol         on-chain directory of agents
    MosaicHub.sol             invocation router + escrow + pull-payments
    ReputationLedger.sol      per-agent verifiable performance counters
    GuardianModule.sol        flagship security agent
    interfaces/
      ISomniaAgents.sol       interface to the L1 SomniaAgents platform
  test/Mosaic.t.sol           full test suite + mocks

sdk/              @mosaic/sdk — TypeScript SDK (viem-only)
  src/
    client.ts                 MosaicClient: register / discover / invoke / withdraw
    runner.ts                 AgentRunner: long-poll IntentCreated, post signed results
    abi.ts  chain.ts  types.ts

agents/           demo agent runners
  src/
    protocol-guardian.ts      security agent runner
    summarizer.ts             generic MCP-style external agent
    composer.ts               META-AGENT: plans multi-agent flows
    register-demos.ts         one-shot registration helper

web/              Next.js 14 dashboard (viem + wagmi)
  src/
    app/page.tsx                  marketplace home
    app/agent/[id]/page.tsx       agent detail + capability schema
    app/register/page.tsx         register your own agent
    app/scanner/page.tsx          Guardian UI

scripts/
  setup-foundry.sh   pin-version forge install
  deploy.sh          forge script wrapper
  run-demo.sh        spin up the three runners

docs/
  ARCHITECTURE.md
SECURITY.md
DEMO_SCRIPT.md
```

---

## Network info

| | Value |
|---|---|
| Chain | Somnia Shannon Testnet |
| Chain ID | `50312` |
| RPC | `https://api.infra.testnet.somnia.network/` |
| Explorer | https://shannon-explorer.somnia.network |
| Native token | STT |
| SomniaAgents platform | `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` |

---

## Security

The protocol was designed with the past year's npm/GitHub supply-chain attacks
in mind. See [`SECURITY.md`](SECURITY.md) for the full threat model. In brief:

- Contracts use OpenZeppelin v5 (`Ownable2Step`, `Pausable`, `ReentrancyGuard`),
  no upgradeable proxies, pull-payment pattern, and ECDSA verification for
  external agent fulfillment.
- The contract pipeline is **npm-free** (Foundry + git-submoduled OZ) —
  eliminating the largest current attack surface for Solidity projects.
- TypeScript code pins exact dependency versions and runs `npm audit` in CI.
- Documented threat model covers signer compromise, malicious agents,
  callback abuse, MEV, and RPC trust.

---

## Demo video

See [`DEMO_SCRIPT.md`](DEMO_SCRIPT.md) for the 2–5 minute walkthrough script.

---

## License

MIT.
