# Security & threat model

Mosaic is a hackathon prototype. It has not been audited. This document
captures the design decisions made to minimize attack surface and the
known threats we did *not* fully mitigate.

## Threat model

| # | Threat | Mitigation |
|---|---|---|
| 1 | **Reentrancy on payment paths** | `ReentrancyGuard` on every payable & state-mutating Hub method. Pull-payment pattern (`withdraw()`) instead of pushing STT to agent owners on settlement. |
| 2 | **Malicious callbacks** | Hub treats user callback failures as a *no-op* for the agent — the fee still settles. Conversely, callbacks reject any sender that isn't the Hub (`require(msg.sender == hub)`). |
| 3 | **Forged off-chain results** | `fulfillIntent` verifies an ECDSA signature over `keccak256(abi.encode(hub, invocationId, result))` against the agent owner recorded in `AgentRegistry`. |
| 4 | **Front-running of fulfillment** | The fulfillment payload includes `invocationId`; signatures are bound to the specific invocation and Hub address, so a replay across invocations or hubs fails. |
| 5 | **Stuck escrow** | `refundExpired` lets the original caller (or the agent owner) reclaim funds 1 hour after an external invocation. The Hub owner can additionally force-refund via the same path. |
| 6 | **Hub owner key compromise** | Hub is `Ownable2Step` (two-step transfer) and `Pausable`. Owner *cannot* drain funds — they hold no privilege over `withdrawable` balances, only over `protocolFeeBps` (hard-capped at 10%) and treasury target. |
| 7 | **Native-agent platform spoofing** | `handleResponse` requires `msg.sender == somniaAgentsPlatform` (immutable at deploy). |
| 8 | **npm supply-chain attacks** | The **contract pipeline is npm-free**: Foundry + git-submoduled OpenZeppelin. Frontend & runners pin exact dependency versions, ship a committed lockfile, and run `npm audit --omit=dev` as part of `make verify`. |
| 9 | **Malicious agent registrations** | Registry is permissionless by design (this is a marketplace). Risk is mitigated by reputation, the Guardian agent's risk score on any contract caller, and the Hub's pause switch in catastrophic cases. |
| 10 | **MEV / sandwich on register/update** | No price-sensitive state in registry; pricing updates are independent of order flow. |
| 11 | **Long-tail validator failures (native)** | Hub forwards Somnia's `Failed` / `TimedOut` status back to the consumer callback and refunds the escrowed Mosaic fee — agent does not earn for a non-result. |
| 12 | **Signer key in agent runners** | Runners hold the agent owner's signing key. Recommended: use a separate hot wallet per agent runner, with an on-chain ownership rotation via `transferAgent` if compromised. |
| 13 | **Bytecode-heuristic false positives in Guardian** | Heuristic is intentionally simple and explainable (see `_onchainScore`). The composite score blends with an off-chain assessment from a runner and is never treated as an automated bar to anything — it is a *recommendation*. |

## Design choices we are conscious of

- **No upgradeable proxies.** Every Mosaic contract is non-upgradeable. This
  trades off forward flexibility for a smaller attack surface and simpler
  reasoning. A new version means a new deployment, not a logic upgrade.
- **No external calls in the registry.** Registration writes only local state
  + emits an event. Discovery is read-only.
- **Cap on protocol fee.** `setProtocolFee` reverts with `FeeTooHigh()` above
  10% (1000 bps).
- **`via_ir = false`.** We compile with the legacy pipeline + optimizer; the
  refactored `MosaicHub.invoke` keeps stack pressure low enough to avoid
  needing the IR pipeline (which historically introduces compile-time and
  audit-time variance). This is verified by the project's compile output.

## Out of scope (known)

- DoS by spamming `register` is possible but bounded by gas + the optional
  protocol fee. A mainnet deployment would gate registration behind a small
  STT deposit.
- The on-chain Guardian heuristic is **a heuristic**, not a full static
  analyzer. Real-world deployment would replace it with a Slither/Mythril-class
  off-chain analyzer published by reputable runners. The marketplace structure
  makes that swap a non-event (just register a higher-scored agent).
