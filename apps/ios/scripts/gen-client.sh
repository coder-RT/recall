#!/usr/bin/env bash
# Copies the bundled API spec into RecallNetworking; Apple's swift-openapi-generator build plugin generates the client
# from it at build time (types + client). Run via `make gen-swift-client`.
set -euo pipefail
spec="${1:?usage: gen-client.sh <bundled openapi.json>}"
dest="$(dirname "$0")/../Packages/RecallKit/Sources/RecallNetworking/openapi.json"
cp "$spec" "$dest"
echo "copied $spec -> $dest"
