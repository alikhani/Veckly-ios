#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_PATH="$ROOT_DIR/OpenAPI/veckly-openapi.json"
CONFIG_PATH="$ROOT_DIR/OpenAPI/openapi-generator-config.yaml"
OUTPUT_DIR="$ROOT_DIR/Veckly/Generated/OpenAPI"
CODEGEN_DIR="$ROOT_DIR/OpenAPI/Codegen"

if [[ ! -f "$SPEC_PATH" ]]; then
  echo "Missing OpenAPI spec at $SPEC_PATH" >&2
  echo "Run npm run openapi:write from Veckly-backend first." >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

swift run \
  --package-path "$CODEGEN_DIR" \
  swift-openapi-generator \
  generate \
  "$SPEC_PATH" \
  --config "$CONFIG_PATH" \
  --output-directory "$OUTPUT_DIR"
