#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Building..."
make -B 2>&1 | grep -v "warning:" | grep -v "note:" || true
echo "Running tests..."
python3 tests/test_proxy.py ./proxyto
