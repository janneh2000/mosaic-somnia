#!/usr/bin/env bash
# Fixes the Guardian agent-ownership bug.
#
# Root cause:
#   GuardianModule.selfRegister() calls AgentRegistry.register() which sets the
#   agent's owner to msg.sender — the GuardianModule contract itself. A contract
#   can't sign EIP-191 messages, so MosaicHub.fulfillIntent() reverts every
#   runner submission with BadSignature() (0x5cd5d233).
#
# Fix:
#   1. Adds selfRegisterAndTransfer(price, metadata, runnerOwner) to
#      GuardianModule, which register()s then transferAgent()s to runnerOwner.
#   2. Updates deploy-manual.sh to call selfRegisterAndTransfer with a new
#      $GUARDIAN_RUNNER_OWNER env var (defaults to $DEPLOYER if unset).
set -euo pipefail

REPO="${REPO:-$HOME/Desktop/mosaic-somnia/mosaic}"
[ -d "$REPO/contracts/src" ] || { echo "✗ $REPO/contracts/src not found"; exit 1; }
[ -f "$REPO/scripts/deploy-manual.sh" ] || { echo "✗ $REPO/scripts/deploy-manual.sh not found"; exit 1; }

############################################
# 1. GuardianModule.sol — replace selfRegister with both functions
############################################
SOL="$REPO/contracts/src/GuardianModule.sol"
cp "$SOL" "$SOL.bak"

python3 - "$SOL" <<'PY'
import sys, re, pathlib
path = pathlib.Path(sys.argv[1])
src = path.read_text()

old = """    /// @notice Self-register Guardian as an external agent (called once at setup).
    function selfRegister(uint256 pricePerInvocation, string calldata metadataURI)
        external
        returns (uint256)
    {
        if (guardianAgentId != 0) revert AlreadyRegistered();
        guardianAgentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL,
            0,
            pricePerInvocation,
            metadataURI,
            \"security\"
        );
        return guardianAgentId;
    }"""

new = """    /// @notice Self-register Guardian as an external agent (called once at setup).
    /// @dev    Owner of the registered agent will be address(this). A contract
    ///         cannot sign EIP-191 messages, so use selfRegisterAndTransfer
    ///         below if you want an off-chain runner wallet to fulfill scans.
    function selfRegister(uint256 pricePerInvocation, string calldata metadataURI)
        external
        returns (uint256)
    {
        if (guardianAgentId != 0) revert AlreadyRegistered();
        guardianAgentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL,
            0,
            pricePerInvocation,
            metadataURI,
            \"security\"
        );
        return guardianAgentId;
    }

    /// @notice Self-register Guardian and immediately transfer the agent record
    ///         to `runnerOwner`, so that runnerOwner's wallet can sign valid
    ///         fulfillments via MosaicHub.fulfillIntent.
    ///         This is the function the deploy script should call in any
    ///         deployment that uses an off-chain Guardian runner.
    function selfRegisterAndTransfer(
        uint256 pricePerInvocation,
        string calldata metadataURI,
        address runnerOwner
    ) external returns (uint256) {
        if (guardianAgentId != 0) revert AlreadyRegistered();
        require(runnerOwner != address(0), \"runnerOwner=0\");
        guardianAgentId = registry.register(
            AgentRegistry.AgentType.EXTERNAL,
            0,
            pricePerInvocation,
            metadataURI,
            \"security\"
        );
        // GuardianModule is the temporary owner (set by register()); transfer
        // to the runner wallet so it can sign personal-sign fulfillments.
        registry.transferAgent(guardianAgentId, runnerOwner);
        return guardianAgentId;
    }"""

if old not in src:
    if "selfRegisterAndTransfer" in src:
        print("  (already patched, skipping)")
        sys.exit(0)
    print("✗ couldn't find the original selfRegister block in GuardianModule.sol")
    sys.exit(1)

path.write_text(src.replace(old, new))
print("✓ patched GuardianModule.sol (added selfRegisterAndTransfer)")
PY

############################################
# 2. deploy-manual.sh — swap selfRegister call for selfRegisterAndTransfer
############################################
DEPLOY="$REPO/scripts/deploy-manual.sh"
cp "$DEPLOY" "$DEPLOY.bak"

python3 - "$DEPLOY" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
src = path.read_text()

old_a = '''DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PK")
TREASURY="${TREASURY:-$DEPLOYER}"'''

new_a = '''DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PK")
TREASURY="${TREASURY:-$DEPLOYER}"
# Wallet that should own the Guardian agent record on-chain. This MUST be an
# EOA whose private key the off-chain Guardian runner can load — a contract
# address (e.g. GuardianModule itself) cannot sign EIP-191 messages, so any
# attempt to fulfillIntent would revert with BadSignature(). Defaults to the
# deployer if not explicitly set.
GUARDIAN_RUNNER_OWNER="${GUARDIAN_RUNNER_OWNER:-$DEPLOYER}"'''

if old_a in src:
    src = src.replace(old_a, new_a)

old_b = '''    METADATA=\'data:application/json,%7B%22name%22%3A%22ProtocolGuardian%22%2C%22kind%22%3A%22security%22%2C%22version%22%3A%221.0.0%22%7D\'
    send "GuardianModule.selfRegister" "$GUARDIAN_MODULE_ADDRESS" \\
        "selfRegister(uint256,string)" "50000000000000000" "$METADATA"
    GUARDIAN_AGENT_ID=$(cast call --rpc-url "$SOMNIA_RPC_URL" \\
        "$GUARDIAN_MODULE_ADDRESS" "guardianAgentId()(uint256)")
    log "  Guardian agent id = $GUARDIAN_AGENT_ID"'''

new_b = '''    METADATA=\'data:application/json,%7B%22name%22%3A%22ProtocolGuardian%22%2C%22kind%22%3A%22security%22%2C%22version%22%3A%221.0.0%22%7D\'
    # Register Guardian AND transfer agent record ownership to the runner EOA
    # in a single tx, so the runner wallet can sign valid EIP-191 fulfillments.
    send "GuardianModule.selfRegisterAndTransfer" "$GUARDIAN_MODULE_ADDRESS" \\
        "selfRegisterAndTransfer(uint256,string,address)" \\
        "50000000000000000" "$METADATA" "$GUARDIAN_RUNNER_OWNER"
    GUARDIAN_AGENT_ID=$(cast call --rpc-url "$SOMNIA_RPC_URL" \\
        "$GUARDIAN_MODULE_ADDRESS" "guardianAgentId()(uint256)")
    log "  Guardian agent id = $GUARDIAN_AGENT_ID"
    log "  Guardian agent owner (must match AGENT_PRIVATE_KEY in agents/.env): $GUARDIAN_RUNNER_OWNER"'''

if old_b in src:
    src = src.replace(old_b, new_b)
elif "selfRegisterAndTransfer" not in src:
    print("✗ couldn't find the selfRegister call block in deploy-manual.sh")
    sys.exit(1)

path.write_text(src)
print("✓ patched deploy-manual.sh (uses selfRegisterAndTransfer)")
PY

cat <<EOF

Backups saved as .bak alongside each patched file.

NEXT STEPS for the redeploy:
  cd $REPO
  forge build
  export DEPLOYER_PK=0x<your_deployer_testnet_key>
  export GUARDIAN_RUNNER_OWNER=0x1D442E07Ba8efAef54e75f6e5411CD0D0019377C
  # ^ THIS is the address whose private key is in agents/.env.
  #   The Guardian agent record will be transferred to this address right
  #   after registration, so its private key can sign fulfillments.

  # Make sure the deployer wallet has at least ~2 STT on Somnia Testnet.
  # Then:
  bash scripts/deploy-manual.sh

The script will print 5 new addresses. Copy them into:
  1. $REPO/web/.env.local             (5 NEXT_PUBLIC_* vars)
  2. Vercel project env settings      (same 5 vars — then trigger a redeploy)
  3. $REPO/agents/.env                (5 *_ADDRESS vars + GUARDIAN_AGENT_ID)

Confirm AGENT_PRIVATE_KEY in agents/.env corresponds to
$GUARDIAN_RUNNER_OWNER (you can sanity check it with the existing
src/whoOwnsGuardian.ts after the redeploy — owner should now be the
runner wallet, NOT a contract address).

Finally, stop the 3 currently-looping runners (Ctrl-C in each terminal)
and restart them from a clean state — they'll pick up both the new
addresses AND the chunked-logs fix.
EOF
