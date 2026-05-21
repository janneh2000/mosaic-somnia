#!/usr/bin/env bash
# Deploy Mosaic to Somnia Shannon testnet.
#
# Required env:
#   DEPLOYER_PK           – hex private key with STT testnet funds
#   SOMNIA_RPC_URL        – defaults to https://api.infra.testnet.somnia.network/
#
# Optional:
#   TREASURY              – treasury address (defaults to deployer)
#   SOMNIA_AGENTS         – override platform address (mainnet vs testnet)
set -euo pipefail

cd "$(dirname "$0")/../contracts"

: "${DEPLOYER_PK:?missing DEPLOYER_PK env var}"
export SOMNIA_RPC_URL="${SOMNIA_RPC_URL:-https://api.infra.testnet.somnia.network/}"

# Somnia testnet's eth_estimateGas returns a value that's significantly
# lower than what the contract actually needs at deploy time, so Foundry
# sets a too-tight gas limit and the tx OOGs. Padding the estimate 4x
# clears the floor. Tweak GAS_MULTIPLIER if you see different behavior.
GAS_MULTIPLIER="${GAS_MULTIPLIER:-400}"

# Default to EIP-1559 (legacy mode disabled). If you see issues, retry with:
#     EXTRA_FORGE_FLAGS="--legacy" make deploy
EXTRA="${EXTRA_FORGE_FLAGS:-}"

forge script script/Deploy.s.sol:Deploy \
    --rpc-url "$SOMNIA_RPC_URL" \
    --broadcast \
    --slow \
    --gas-estimate-multiplier "$GAS_MULTIPLIER" \
    ${EXTRA} \
    -vvvv
