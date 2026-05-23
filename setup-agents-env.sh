#!/usr/bin/env bash
# Creates mosaic/agents/.env from the values already in mosaic/web/.env.local.
# Run this on your Mac from inside the repo root (~/Desktop/mosaic-somnia/mosaic).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/Desktop/mosaic-somnia/mosaic}"
WEB_ENV="$REPO_ROOT/web/.env.local"
AGENTS_ENV="$REPO_ROOT/agents/.env"

if [ ! -f "$WEB_ENV" ]; then
    echo "✗ couldn't find $WEB_ENV"
    echo "  Set REPO_ROOT=/path/to/mosaic and re-run."
    exit 1
fi

# Pull the addresses from the existing web env file.
get() { grep -E "^$1=" "$WEB_ENV" | head -1 | cut -d= -f2- ; }

RPC="$(get NEXT_PUBLIC_SOMNIA_RPC)"
REG="$(get NEXT_PUBLIC_AGENT_REGISTRY)"
HUB="$(get NEXT_PUBLIC_MOSAIC_HUB)"
REP="$(get NEXT_PUBLIC_REPUTATION_LEDGER)"
GRD="$(get NEXT_PUBLIC_GUARDIAN_MODULE)"

mkdir -p "$(dirname "$AGENTS_ENV")"
cat > "$AGENTS_ENV" <<EOF
# --- mosaic/agents/.env -------------------------------------------------------
# Auto-generated from web/.env.local. Edit AGENT_PRIVATE_KEY + the *_AGENT_ID
# values below before starting the runners.

SOMNIA_RPC_URL=$RPC

# Runner wallet. Use a fresh testnet key — DO NOT reuse your personal key.
# Fund it with at least 1 STT from https://testnet.somnia.network/
AGENT_PRIVATE_KEY=0xREPLACE_ME_WITH_TESTNET_PRIVATE_KEY

# Contract addresses (same as the frontend, renamed for the runner config)
AGENT_REGISTRY_ADDRESS=$REG
MOSAIC_HUB_ADDRESS=$HUB
REPUTATION_LEDGER_ADDRESS=$REP
GUARDIAN_MODULE_ADDRESS=$GRD

# Agent IDs printed by the deploy / register-demos scripts.
# Guardian is registered by the Deploy script. Summarizer + Composer come from
# 'npm run register-demos'. Defaults below match the common deploy order.
GUARDIAN_AGENT_ID=1
SUMMARIZER_AGENT_ID=4
COMPOSER_AGENT_ID=5
EOF

chmod 600 "$AGENTS_ENV"
echo "✓ wrote $AGENTS_ENV"
echo
echo "Next steps:"
echo "  1. open $AGENTS_ENV and set AGENT_PRIVATE_KEY to your testnet runner key"
echo "  2. confirm GUARDIAN_AGENT_ID / SUMMARIZER_AGENT_ID / COMPOSER_AGENT_ID"
echo "     match the IDs printed at deploy / register-demos time. If you don't"
echo "     remember them, run:    cd agents && npm run register-demos"
echo "  3. start the runners:"
echo "       cd agents"
echo "       npm install"
echo "       npm run guardian    # terminal 1"
echo "       npm run summarizer  # terminal 2"
echo "       npm run composer    # terminal 3"
echo
echo "Your pending scan will be picked up automatically once the guardian"
echo "runner connects — no need to re-pay 0.05 STT."
