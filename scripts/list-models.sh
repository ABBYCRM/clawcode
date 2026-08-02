#!/usr/bin/env bash
# scripts/list-models.sh
# List available models from each configured provider.
# Usage:
#   ./scripts/list-models.sh          # all providers
#   ./scripts/list-models.sh nvidia   # just NVIDIA NIM
#   ./scripts/list-models.sh bitdeer  # just Bitdeer

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

[ -f .env ] && { set -a; . ./.env; set +a; }

TARGET="${1:-all}"

list_nvidia() {
  echo ""
  echo "=== NVIDIA NIM models ==="
  KEY="${NVIDIA_NIM_KEY_1:-}"
  if [ -z "$KEY" ]; then
    echo "SKIP: NVIDIA_NIM_KEY_1 not set"; return 0
  fi
  curl -sS --max-time 15 "${NVIDIA_NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}/models" \
    -H "Authorization: Bearer $KEY" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); [print('  ',m['id']) for m in sorted(d.get('data',[]), key=lambda x:x['id'])]"
}

list_bitdeer() {
  echo ""
  echo "=== Bitdeer models ==="
  KEY="${BITDEER_API_KEY:-}"
  if [ -z "$KEY" ]; then
    echo "SKIP: BITDEER_API_KEY not set"; return 0
  fi
  curl -sS --max-time 15 "${BITDEER_BASE_URL:-https://api-inference.bitdeer.ai/v1}/models" \
    -H "Authorization: Bearer $KEY" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); [print('  ',m['id']) for m in sorted(d.get('data',[]), key=lambda x:x['id'])]"
}

case "$TARGET" in
  nvidia)    list_nvidia ;;
  bitdeer)   list_bitdeer ;;
  all)       list_nvidia; list_bitdeer ;;
  *)         echo "Usage: $0 [all|nvidia|bitdeer]"; exit 1 ;;
esac
