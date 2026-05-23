#!/usr/bin/env bash
# Updates web/.env.local and agents/.env to point at the freshly-deployed
# contracts. Run after a successful deploy-manual.sh run.
set -euo pipefail

REPO="${REPO:-$HOME/Desktop/mosaic-somnia/mosaic}"

# New addresses from the May 23 redeploy
AGENT_REGISTRY=0x6F859eB61f03406F1661B58006FBd95D7844df42
REPUTATION_LEDGER=0xd9Eb130D8E346703AeF0A27318f7a70201A696b5
MOSAIC_HUB=0x885eEd164a427939E69dB1bC28b55Fca5cD60b93
GUARDIAN_MODULE=0xA42c2B930daE19E35dC62d94eB22616e89c270cA
GUARDIAN_AGENT_ID=1

WEB_ENV="$REPO/web/.env.local"
AGENTS_ENV="$REPO/agents/.env"

# Cross-platform sed-in-place (macOS sed needs an explicit empty backup arg)
upd() {
    local file="$1" key="$2" val="$3"
    if grep -qE "^${key}=" "$file"; then
        sed -i.bak -E "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

# --- web/.env.local ----------------------------------------------------------
if [ -f "$WEB_ENV" ]; then
    upd "$WEB_ENV" NEXT_PUBLIC_AGENT_REGISTRY     "$AGENT_REGISTRY"
    upd "$WEB_ENV" NEXT_PUBLIC_REPUTATION_LEDGER  "$REPUTATION_LEDGER"
    upd "$WEB_ENV" NEXT_PUBLIC_MOSAIC_HUB          "$MOSAIC_HUB"
    upd "$WEB_ENV" NEXT_PUBLIC_GUARDIAN_MODULE     "$GUARDIAN_MODULE"
    echo "✓ updated $WEB_ENV"
else
    echo "✗ $WEB_ENV not found — skipping"
fi

# --- agents/.env -------------------------------------------------------------
if [ -f "$AGENTS_ENV" ]; then
    upd "$AGENTS_ENV" AGENT_REGISTRY_ADDRESS      "$AGENT_REGISTRY"
    upd "$AGENTS_ENV" REPUTATION_LEDGER_ADDRESS   "$REPUTATION_LEDGER"
    upd "$AGENTS_ENV" MOSAIC_HUB_ADDRESS          "$MOSAIC_HUB"
    upd "$AGENTS_ENV" GUARDIAN_MODULE_ADDRESS     "$GUARDIAN_MODULE"
    upd "$AGENTS_ENV" GUARDIAN_AGENT_ID           "$GUARDIAN_AGENT_ID"
    echo "✓ updated $AGENTS_ENV"
else
    echo "✗ $AGENTS_ENV not found — skipping"
fi

cat <<EOF

──────────────────────────────────────────────────────────────────────
LOCAL ENV UPDATED.  Two manual steps remain:
──────────────────────────────────────────────────────────────────────

1. Update Vercel env vars (the dashboard at vercel.com → your project →
   Settings → Environment Variables → edit each row for Production+Preview):

     NEXT_PUBLIC_AGENT_REGISTRY     = $AGENT_REGISTRY
     NEXT_PUBLIC_REPUTATION_LEDGER  = $REPUTATION_LEDGER
     NEXT_PUBLIC_MOSAIC_HUB         = $MOSAIC_HUB
     NEXT_PUBLIC_GUARDIAN_MODULE    = $GUARDIAN_MODULE
     (NEXT_PUBLIC_SOMNIA_RPC is unchanged)

   Then click Redeploy on the latest production deployment.

2. Stop and restart the 3 local runners so they pick up the new
   addresses + chunked-logs fix:

     # in each of the three runner terminals: Ctrl-C
     cd $REPO/agents
     set -a; source .env; set +a
     npm run guardian       # terminal 1
     npm run summarizer     # terminal 2
     npm run composer       # terminal 3

3. Sanity check the on-chain owner one more time:
     cd $REPO/agents
     npx tsx --env-file=.env src/whoOwnsGuardian.ts
   Expect:
     on-chain owner:  0x1D442E07Ba8efAef54e75f6e5411CD0D0019377C
     (a wallet, NOT a contract)

4. Go to mosaic-somnia.vercel.app → Scanner → enter any contract address
   → "Request scan (0.05 STT)". Watch the guardian terminal — should print
   [runner] fulfilling invocation=… then [runner] fulfilled tx=0x…
   Report card appears in the dashboard.
EOF
