#!/usr/bin/env bash
# Preflight check for a fresh clone. Verifies env files exist and required
# values are filled in before you try to deploy, register, or run the runners.
# Safe to run anytime: read-only, never writes or mounts anything.
set -uo pipefail

cd "$(dirname "$0")/.."

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
fail=0

ok()   { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
bad()  { printf "  ${RED}✗${RESET} %s\n" "$1"; fail=1; }
warn() { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }

ZERO_ADDR="0x0000000000000000000000000000000000000000"
ZERO_KEY="0x0000000000000000000000000000000000000000000000000000000000000000"

# Pull a KEY=value out of a dotenv file (last wins, strips quotes/whitespace).
getval() { grep -E "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"'"'"' ' ; }

echo "Mosaic doctor — fresh-clone preflight"
echo

# 1. Tooling
echo "Tooling:"
command -v node  >/dev/null 2>&1 && ok "node $(node -v)"  || bad "node not found (need >=20)"
command -v npm   >/dev/null 2>&1 && ok "npm $(npm -v)"     || bad "npm not found"
command -v forge >/dev/null 2>&1 && ok "forge $(forge --version | head -1)" \
    || warn "forge not found — run 'make setup' (only needed to build/deploy contracts)"
echo

# 2. agents/.env
echo "agents/.env:"
if [ -f agents/.env ]; then
    ok "file exists"
    for v in AGENT_PRIVATE_KEY AGENT_REGISTRY_ADDRESS MOSAIC_HUB_ADDRESS \
             REPUTATION_LEDGER_ADDRESS GUARDIAN_MODULE_ADDRESS GUARDIAN_AGENT_ID; do
        val="$(getval agents/.env "$v")"
        if [ -z "$val" ]; then bad "$v is empty"
        elif [ "$val" = "$ZERO_ADDR" ] || [ "$val" = "$ZERO_KEY" ]; then bad "$v still a placeholder"
        else ok "$v set"; fi
    done
    for v in SUMMARIZER_AGENT_ID COMPOSER_AGENT_ID; do
        [ -z "$(getval agents/.env "$v")" ] && warn "$v empty (set after 'npm run register-demos')" || ok "$v set"
    done
else
    bad "missing — run: cp agents/.env.example agents/.env"
fi
echo

# 3. web/.env.local
echo "web/.env.local:"
if [ -f web/.env.local ]; then
    ok "file exists"
    for v in NEXT_PUBLIC_SOMNIA_RPC NEXT_PUBLIC_AGENT_REGISTRY NEXT_PUBLIC_MOSAIC_HUB \
             NEXT_PUBLIC_REPUTATION_LEDGER NEXT_PUBLIC_GUARDIAN_MODULE; do
        val="$(getval web/.env.local "$v")"
        if [ -z "$val" ]; then bad "$v is empty"
        elif [ "$val" = "$ZERO_ADDR" ]; then bad "$v still a placeholder"
        else ok "$v set"; fi
    done
else
    bad "missing — run: cp web/.env.example web/.env.local"
fi
echo

if [ "$fail" -eq 0 ]; then
    printf "${GREEN}All checks passed.${RESET} You're ready to run: make register / make run-agents / make web\n"
else
    printf "${RED}Some checks failed.${RESET} Fix the items above, then re-run: make doctor\n"
    printf "${DIM}Addresses come from scripts/deploy-manual.sh; agent IDs from 'npm run register-demos'.${RESET}\n"
    exit 1
fi
