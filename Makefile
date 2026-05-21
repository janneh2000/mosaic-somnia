.PHONY: setup build test deploy register run-agents web verify clean help

help:
	@echo "Mosaic — common targets"
	@echo "  make setup      → install foundry deps for contracts/"
	@echo "  make build      → forge build"
	@echo "  make test       → forge test (unit tests, full suite)"
	@echo "  make deploy     → deploy to Somnia testnet (set DEPLOYER_PK)"
	@echo "  make register   → register the demo external agents"
	@echo "  make run-agents → start all off-chain agent runners"
	@echo "  make web        → install + dev-run the Next.js dashboard"
	@echo "  make verify     → end-to-end sanity check"
	@echo "  make clean      → wipe build artifacts"

setup:
	./scripts/setup-foundry.sh
	cd sdk && npm install --no-audit --no-fund
	cd agents && npm install --no-audit --no-fund

build:
	cd contracts && forge build

test:
	cd contracts && forge test -vvv

deploy:
	./scripts/deploy-manual.sh

register:
	cd agents && npm run register-demos

run-agents:
	./scripts/run-demo.sh

web:
	cd web && npm install --no-audit --no-fund && npm run dev

verify:
	cd contracts && forge build && forge test
	cd sdk && npm run typecheck
	cd agents && npm run typecheck
	cd web && npm run typecheck

clean:
	cd contracts && forge clean
	rm -rf sdk/dist agents/dist web/.next
