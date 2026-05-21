# Mosaic — 3-minute demo script

Target length: ~3 minutes. All on-screen actions are live against Somnia
Shannon Testnet — no fake data.

---

## [00:00 — 00:20] The hook

> "Somnia's L1 lets smart contracts call AI and APIs natively, with
> validator-consensus on the result. That is the substrate.
> But there's no way for one agent to **discover** or **pay** another. There's
> no on-chain reputation. There's no bridge to the MCP ecosystem.
>
> Mosaic adds that layer."

**Show on screen**: the Mosaic landing page at `localhost:3000` — list of
registered agents, each with a reputation badge and capability tag.

---

## [00:20 — 00:55] Discover & invoke

**Action**: Click on **Protocol Guardian** in the marketplace.

> "Every agent has an MCP-compatible capability schema stored on-chain.
> Here's Protocol Guardian — a security agent. It exposes a `scan` method
> that takes any contract address."

**Action**: Switch to `/scanner`. Connect wallet. Paste a contract address
(e.g. the freshly deployed `MosaicHub` itself), click **Request scan**.

> "I'm requesting an on-chain scan. Behind the scenes, the Guardian
> contract emitted an `IntentCreated` event on MosaicHub. An off-chain runner
> picked it up, ran a heuristic analysis of the bytecode, signed the result
> with the Guardian's owner key, and posted it back through the Hub.
> The Hub verified the signature, settled the fee into pull-payment, and
> called the Guardian's callback. The Guardian combined the off-chain
> assessment with a fresh on-chain bytecode scan to produce a composite
> risk score."

**Show on screen**: the composite risk score, findings list, off-chain
JSON payload.

---

## [00:55 — 01:40] Composability — the meta-agent

> "Now the part that makes this an *agent* marketplace, not just a
> service marketplace."

**Action**: Back at the marketplace, open **Composer** (capability tag
`composer`).

> "Composer is a *meta-agent*. It takes a high-level goal — for example
> `audit_and_explain` — queries the registry on-chain, ranks every security
> agent and every summarizer by their on-chain reputation, picks the best
> in each, and plans the multi-agent flow.
>
> Watch the logs."

**Action**: In the terminal, show the composer's log line:

```
[composer] received goal="audit_and_explain" target="0x..."
[composer] generated plan (348 chars)
```

> "Every step of that plan is an autonomous agent invocation that earns
> its operator STT and updates its on-chain reputation. No orchestrator.
> No central scheduler. Pure agent-to-agent."

---

## [01:40 — 02:10] Native + external in one registry

**Action**: Back at the marketplace, point at the "Somnia native" badge
on an agent.

> "Mosaic doesn't care whether the agent is run by Somnia's validator
> network — like the built-in JSON API agent — or by an off-chain runner
> implementing the MCP protocol. They're both first-class entries in the
> same registry. A consumer contract gets the same callback shape either
> way. So a developer who already has an MCP server today can register it
> in 30 seconds and start earning STT on Somnia."

**Action**: Quickly click **Register** in the nav — show the form.

---

## [02:10 — 02:40] Security & resilience

> "The contracts are deployed live to Shannon Testnet. The Hub uses
> OpenZeppelin's `Ownable2Step`, `Pausable`, and `ReentrancyGuard`. Payouts
> go through a pull-payment pattern — agent owners call `withdraw()`,
> nothing is pushed. Off-chain fulfillment is gated by an ECDSA signature
> over the hub address + invocation id + result, bound to the agent's
> registered owner.
>
> Given the past year's npm and GitHub supply-chain attacks, the contract
> pipeline is intentionally npm-free — just Foundry plus git-submoduled
> OpenZeppelin. The frontend pins exact dependency versions and ships a
> committed lockfile."

---

## [02:40 — 03:00] Close

> "Mosaic turns Somnia's Agentic L1 from a powerful primitive into an
> *ecosystem*. Agents discover each other. They pay each other. They
> compose. Their reputations are on-chain truth.
>
> Repo's open-source, contracts are live on testnet, demo runs end-to-end.
> Thanks."

**Show on screen**: GitHub URL + Shannon Explorer URL for the deployed Hub.

---

## Pre-recording checklist

- [ ] `forge test` passes locally
- [ ] Contracts deployed to Shannon, addresses saved
- [ ] Guardian + summarizer + composer runners all up
- [ ] Frontend `.env.local` filled in and `npm run dev` running
- [ ] Wallet has at least 0.5 STT for the live scan demo
- [ ] Browser zoom 150% so addresses are readable in the recording
- [ ] Terminal split: top half = runner logs, bottom half = bash for any
      live commands
