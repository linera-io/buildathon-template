#!/usr/bin/env bash

set -euxo pipefail

# 1) Spin up a localnet with faucet and helper env vars
eval "$(linera net helper)"
linera_spawn linera net up --with-faucet

export LINERA_FAUCET_URL=http://localhost:8080
linera wallet init --faucet="$LINERA_FAUCET_URL"
linera wallet request-chain --faucet="$LINERA_FAUCET_URL"

# 2) Build contracts to Wasm (if present in /build/contracts)
if [ -d "/build/contracts" ]; then
  cd /build/contracts
  rustup target add wasm32-unknown-unknown || true
  cargo build --release --target wasm32-unknown-unknown || true
  cd /build
fi

# 3) Publish and create application for hello-contract if available
HELLO_CONTRACT_WASM=/build/contracts/hello/target/wasm32-unknown-unknown/release/hello_contract.wasm
HELLO_SERVICE_WASM=/build/contracts/hello-service/target/wasm32-unknown-unknown/release/hello_service.wasm

if [ -f "$HELLO_CONTRACT_WASM" ] && [ -f "$HELLO_SERVICE_WASM" ]; then
  BYTECODE_ID=$(linera publish-bytecode "$HELLO_CONTRACT_WASM" "$HELLO_SERVICE_WASM")
  APP_ID=$(linera create-application "$BYTECODE_ID" --json-argument "null")
  echo "Published hello bytecode: $BYTECODE_ID"
  echo "Created hello application: $APP_ID"
else
  echo "Hello contract/service Wasm not found; skipping publish/create."
fi

# 4) Start the wallet node service (GraphQL)
linera service --port 8080 &

# 5) Build and run the frontend on port 5173
if [ -d "/build/frontend" ]; then
  cd /build/frontend
  # Use pnpm if available; fallback to npm
  if command -v pnpm >/dev/null 2>&1; then
    pnpm install --prefer-frozen-lockfile=false
    pnpm dev --host 0.0.0.0
  else
    npm install --no-audit --no-fund
    npm run dev -- --host 0.0.0.0
  fi
else
  echo "No /build/frontend directory found. Container healthcheck will fail unless a web server binds :5173."
  # Keep the container running to allow manual interaction
  tail -f /dev/null
fi
