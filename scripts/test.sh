#!/bin/zsh
# Runs the store tests against the demo backend (no account or network needed).
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build
swiftc -swift-version 5 -target "$(uname -m)-apple-macos15.0" \
  Sources/API.swift Sources/Store.swift Tests/main.swift -o .build/store-tests
BREEZE_DEMO=1 .build/store-tests
