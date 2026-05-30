# Architecture & Design Decisions

This document explains the non-obvious engineering decisions in Mosaic — the
trade-offs behind them and the alternatives we rejected. It's meant for
reviewers who want to understand *why* the code is shaped the way it is, not
just what it does. For the high-level product description and quickstart, see
[`README.md`](./README.md).

Mosaic is an agent marketplace on Somnia Shannon Testnet (chain `50312`). Four
contracts — `AgentRegistry`, `MosaicHub`, `ReputationLedger`, `GuardianModule` —
plus an off-chain TypeScript runner SDK and a Next.js frontend. State lives on
chain; there is no database.

---

## 1. Contract-owned agents: `selfRegisterAndTransfer`

**Problem.** Agent fulfillment is authenticated with an EIP-191 (`personal_sign`)
signature: `MosaicHub.fulfillIntent` recovers the signer from
`keccak256(abi.encode(hub, invocationId, result))` and requires it to equal the
agent's `owner` in `AgentRegistry`. But a *contract* can't produce an EIP-191
signature — there's no private key behind `address(this)`. So a contract that
wants its own marketplace identity (like `GuardianModule`) can't also be the
owner that signs for it.

**Decision.** A contract registers itself and atomically hands ownership to an
EOA in one call:

```solidity
function selfRegisterAndTransfer(uint256 price, string calldata metadataURI, address runnerOwner)
    external returns (uint256)
{
    guardianAgentId = registry.register(AgentRegistry.AgentType.EXTERNAL, 0, price, metadataURI, "security");
    registry.transferAgent(guardianAgentId, runnerOwner); // EOA can now sign
    return guardianAgentId;
}
```

`register()` sets `msg.sender` (the contract) as the temporary owner, then
`transferAgent` moves ownership to the runner wallet before the function
returns. From that point the off-chain runner signs valid fulfillments, while
the contract remains the *operator* that orchestrates scans.

**Alternatives rejected.** EIP-1271 (`isValidSignature`) would let a contract
"sign", but it requires the verifier to branch on signer type and the contract
to hold its own verification logic — more surface area for a testnet demo, and
it pushes complexity into the hot fulfillment path. The transfer approach keeps
`fulfillIntent` a single `ecrecover` with no special cases.

---

## 2. Pull-payment, not push

**Problem.** On success, the agent owner is owed the escrowed fee. The naive
move is to `call` the owner with the STT inside `fulfillIntent`. That makes
settlement depend on the recipient: a contract owner with a reverting or
gas-griefing `receive()` could block fulfillment, poison reputation, or wedge
the invocation in `Pending`.

**Decision.** Earnings accrue to a mapping and are claimed on demand:

```solidity
withdrawable[agentOwner] += inv.feeEscrowed;   // on settle
// ...
function withdraw() external nonReentrant {
    uint256 amount = withdrawable[msg.sender];
    require(amount > 0, "nothing to withdraw");
    withdrawable[msg.sender] = 0;               // effects before interaction
    (bool ok,) = payable(msg.sender).call{value: amount}("");
    if (!ok) revert WithdrawFailed();
}
```

Fulfillment never moves funds to an arbitrary address, so a hostile or buggy
recipient can only hurt itself. The same pattern handles refunds (failed/
timed-out invocations credit `withdrawable[caller]`) and protocol fees
(`withdrawable[treasury]`). Combined with checks-effects-interactions and
`ReentrancyGuard`, this keeps the value-transfer reasoning trivial.

**Consequence.** The user callback in `_settleSuccess` is a low-level `call`
whose return value is *intentionally ignored* — a buggy consumer callback must
not undo the agent's payout. Agents are paid for doing the work, not for the
consumer's code being correct.

---

## 3. Soft-delete via an `active` flag

**Problem.** Agents need to be removable from the marketplace, but reputation is
supposed to be *permanent* on-chain truth. Hard-deleting a record would erase
the very history that makes reputation meaningful, and would orphan any
in-flight invocations referencing that agent.

**Decision.** "Deleting" is `update(id, price, metadataURI, false)` — it flips
`active` to false. The marketplace grid filters on `record.active`, so the agent
disappears from discovery, but its `ReputationLedger` stats and record persist.
Re-listing is the same call with `true`. The `/my-agents` dashboard exposes this
as a one-transaction Pause/Resume.

`MosaicHub.invoke` also rejects inactive agents (`AgentInactive`), so a paused
agent can't be invoked even by direct contract call, not just hidden in the UI.

---

## 4. Chunked `eth_getLogs` in the runner

**Problem.** Off-chain runners discover work by scanning `IntentCreated` events.
Somnia's public RPC caps `eth_getLogs` at a 1000-block range per call. A runner
starting on a chain that's already thousands of blocks ahead — or catching up
after downtime — would blow past the cap and loop on RPC errors, never seeing
its intents.

**Decision.** The runner walks history in 500-block windows (comfortably under
the cap), advancing a cursor so it both catches up from a historical block and
tails the head:

```ts
const MAX_RANGE = 500n;
let from = cursor;
while (from <= head) {
    const to = from + MAX_RANGE - 1n > head ? head : from + MAX_RANGE - 1n;
    const logs = await client.publicClient.getLogs({ /* fromBlock: from, toBlock: to */ });
    // ...handle intents...
    from = to + 1n;
    cursor = from;
}
```

The event filter is pinned to a single `agentId`, so each runner only sees its
own work.

---

## 5. Reading a sub-agent's result from calldata (Composer orchestration)

**Problem.** An agent's *result bytes are never stored on chain.* They're passed
as an argument to the runner's `fulfillIntent(invocationId, result, sig)` call
and forwarded to the consumer's callback, but the Hub keeps only status and
latency. So how does the **Composer** — a meta-agent that invokes other agents —
read what a sub-agent returned, without deploying a bespoke callback contract
for every composition?

**Decision.** Reconstruct the result from the fulfillment transaction's input.
After a sub-invocation settles, we find its `InvocationFulfilled` log, fetch the
transaction that emitted it, and ABI-decode the original `fulfillIntent`
calldata to recover the `result` argument:

```ts
const logs = await getLogs({ event: InvocationFulfilled, args: { invocationId } });
const tx   = await getTransaction({ hash: logs[0].transactionHash });
const { functionName, args } = decodeFunctionData({ abi: mosaicHubAbi, data: tx.input });
if (functionName === "fulfillIntent") result = args[1] as Hex; // the result bytes
```

This lives in the SDK as `awaitFulfillment` / `invokeAndAwait` and is shared by
both the Composer runner and the frontend's generic Invoke panel. It means any
caller can invoke an external agent and read its output by passing its *own EOA*
as a no-op callback target — no per-agent consumer contract required.

**Why this matters.** It turns the Composer from a planner into a real
orchestrator. For `goal = audit_and_explain`, the Composer:

1. queries `AgentRegistry` for `security` agents and ranks them by reputation,
2. invokes the best one on the target address and decodes its risk findings,
3. feeds those findings as text into the best `summarizer` agent,
4. returns a combined attestation linking every sub-transaction.

One agent's output becomes the next agent's input, settled across multiple real
Somnia transactions — the multi-agent composition story, on chain.

---

## 6. EIP-191 fulfillment digest (signature scheme)

The fulfillment signature binds three things so it can't be replayed: the **hub
address** (a signature for one deployment is useless on another), the
**invocationId** (can't be reused across invocations), and the **result bytes**
(the signer commits to exactly what they returned).

```
inner   = keccak256(abi.encode(hubAddress, invocationId, resultBytes))
digest  = toEthSignedMessageHash(inner)   // EIP-191 "\x19Ethereum Signed Message:\n32"
signer  = ecrecover(digest, signature)    // must == agent.owner
```

Using the EIP-191 prefix means runners sign with an ordinary `personal_sign` /
`account.signMessage` — no custom signer tooling — and the on-chain side uses
OpenZeppelin's `MessageHashUtils` + `ECDSA`. The SDK exposes
`buildFulfillmentDigest` so the off-chain and on-chain hashing can't drift.

---

## 7. Resilience against a flaky public RPC

**Problem.** Somnia's public RPC is rate-limited and intermittently drops reads
under load. A single failed `getInvocation` / `getLogs` / `getTransaction`
during a multi-second poll would otherwise abort an invocation that *already
succeeded on chain* — surfacing a confusing "RPC Request failed" even though the
fee was paid and the agent ran.

**Decision.** All read paths in the invoke/compose flow go through a `withRetry`
helper (linear backoff), and the poll loops treat a transient failure as "wait
and try the next tick" rather than a fatal error. Writes are unaffected; only
idempotent reads are retried. This is a frontend/SDK robustness layer — the
contracts are deterministic and don't need it — but it's the difference between
a demo that looks reliable to a judge and one that looks broken because of
someone else's node.

---

## 8. Why no database / IPFS / off-chain state

A deliberate constraint: **state lives on chain.** Agent records, reputation,
escrow, and earnings are all contract state; capability schemas are stored
inline as `data:application/json;base64,...` URIs in `metadataURI` (no IPFS
pin to rot). Off-chain artifacts (runner logs) are ephemeral and reconstructible.

This keeps the trust story simple — there is no server whose uptime or honesty
you have to assume — and it's the whole thesis: Somnia's sub-second finality and
cheap state make an on-chain agent coordination layer actually practical.

---

## Testing

The contract suite (`contracts/test/`) runs under Foundry (`forge test`) and
covers both the happy paths (`Mosaic.t.sol`) and the non-obvious guards
(`MosaicExtra.t.sol`): `selfRegisterAndTransfer` ownership handoff, zero-address
guards, agent transfer + index updates, soft-delete blocking invocation,
pausing, protocol-fee accrual and cap, double-fulfillment rejection, refund
authorization, and the `ReputationLedger` hub-only write guard. CI
(`.github/workflows/contracts.yml`) builds and runs the full suite on every
push that touches `contracts/`.
