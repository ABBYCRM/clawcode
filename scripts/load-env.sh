#!/usr/bin/env bash
# scripts/load-env.sh
# Load .env (or .env.example if .env doesn't exist) into the current shell.
# Usage: source scripts/load-env.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -f .env ]; then
  ENV_FILE=".env"
elif [ -f .env.example ]; then
  echo "WARN: .env not found, falling back to .env.example (no real keys)" >&2
  ENV_FILE=".env.example"
else
  echo "ERROR: neither .env nor .env.example found in $ROOT_DIR" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

echo "Loaded $ENV_FILE — env vars set:"
echo "  OPENAI_BASE_URL=${OPENAI_BASE_URL:-<unset>}"
echo "  BITDEER_API_KEY=${BITDEER_API_KEY:+<set>}"
echo "  NVIDIA_NIM_KEY_1=${NVIDIA_NIM_KEY_1:+<set>}"
echo "  CLAW_MODEL=${CLAW_MODEL:-<unset>}"
echo ""
echo "Run a smoke test:  ./scripts/test-providers.sh"
