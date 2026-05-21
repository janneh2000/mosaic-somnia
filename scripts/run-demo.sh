#!/usr/bin/env bash
# End-to-end demo:
#   1. registers summarizer + composer agents
#   2. spawns the guardian, summarizer, composer runners
#   3. tails their logs
set -euo pipefail

cd "$(dirname "$0")/.."

REQUIRED=(AGENT_PRIVATE_KEY AGENT_REGISTRY_ADDRESS MOSAIC_HUB_ADDRESS REPUTATION_LEDGER_ADDRESS GUARDIAN_MODULE_ADDRESS GUARDIAN_AGENT_ID)
for v in "${REQUIRED[@]}"; do
    : "${!v:?missing $v env var}"
done

cd agents
npm install --no-audit --no-fund

# Register summarizer + composer if not already done
if [ -z "${SUMMARIZER_AGENT_ID:-}" ] || [ -z "${COMPOSER_AGENT_ID:-}" ]; then
    echo "→ registering demo agents…"
    npm run register-demos
    echo
    echo "→ export the printed IDs and re-run this script"
    exit 0
fi

mkdir -p logs

echo "→ starting guardian runner…"
npm run guardian      > logs/guardian.log     2>&1 &
echo "→ starting summarizer runner…"
npm run summarizer    > logs/summarizer.log   2>&1 &
echo "→ starting composer runner…"
npm run composer      > logs/composer.log     2>&1 &

echo
echo "✓ runners launched. tail with:"
echo "    tail -F agents/logs/*.log"
wait
