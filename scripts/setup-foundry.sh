#!/usr/bin/env bash
# Bootstrap the contracts/ subproject's Foundry dependencies.
# Run from the repo root.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v forge >/dev/null 2>&1; then
    echo "❌ foundry not installed. Install with:"
    echo "    curl -L https://foundry.paradigm.xyz | bash && foundryup"
    exit 1
fi

cd contracts

# Pinned versions — bump deliberately, not casually.
OPENZEPPELIN_TAG="v5.0.2"
FORGE_STD_TAG="v1.9.2"

# Init git if needed so forge install works.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git init -q
    git add -A
    git -c user.email=ci@local -c user.name=ci commit -m "init" -q || true
fi

mkdir -p lib

if [ ! -d lib/openzeppelin-contracts ]; then
    forge install OpenZeppelin/openzeppelin-contracts@${OPENZEPPELIN_TAG}
fi
if [ ! -d lib/forge-std ]; then
    forge install foundry-rs/forge-std@${FORGE_STD_TAG}
fi

echo "✓ foundry deps installed:"
echo "    OZ: ${OPENZEPPELIN_TAG}"
echo "    forge-std: ${FORGE_STD_TAG}"
echo
echo "next: forge build  &&  forge test"
