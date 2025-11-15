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
  # Ensure WASM target is available
  rustup target add wasm32-unknown-unknown || true
  # Build all contract crates to Wasm, ignore failures to allow frontend-only demos
  cargo build --release --target wasm32-unknown-unknown || true
  cd /build
fi

# 3) Optionally publish and create application if contract+service are available
# Set CONTRACT_WASM and SERVICE_WASM to actual paths if you have both
CONTRACT_WASM=${CONTRACT_WASM:-/build/contracts/target/wasm32-unknown-unknown/release/app_contract.wasm}
SERVICE_WASM=${SERVICE_WASM:-/build/contracts/target/wasm32-unknown-unknown/release/app_service.wasm}

if [ -f "$CONTRACT_WASM" ] && [ -f "$SERVICE_WASM" ]; then
  BYTECODE_ID=$(linera publish-bytecode "$CONTRACT_WASM" "$SERVICE_WASM")
  # Provide a minimal JSON argument; adjust to your app
  APP_ID=$(linera create-application "$BYTECODE_ID" --json-argument "null")
  echo "Published bytecode: $BYTECODE_ID"
  echo "Created application: $APP_ID"
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
