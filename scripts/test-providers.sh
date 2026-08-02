#!/usr/bin/env bash
# scripts/test-providers.sh
# Smoke test for configured Bitdeer + NVIDIA NIM endpoints.
# Reads .env if present, else falls back to .env.example (which has no real keys).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Load env
if [ -f .env ]; then
  set -a; . ./.env; set +a
elif [ -f .env.example ]; then
  echo "WARN: .env missing, using .env.example (no real keys — most tests will fail)" >&2
  set -a; . ./.env.example; set +a
fi

PASS=0
FAIL=0

run_test() {
  local name="$1"
  local base="$2"
  local key="$3"
  local model="$4"
  echo ""
  echo "TEST: $name"
  echo "  base:  $base"
  echo "  model: $model"
  if [ -z "$key" ] || [ "$key" = "REPLACE_ME" ]; then
    echo "  SKIP: no key configured"
    return 0
  fi
  RESP=$(curl -sS --max-time 30 "$base/chat/completions" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"$model\",
      \"messages\": [{\"role\":\"user\",\"content\":\"Reply exactly: HELLO_$(echo $name | tr '[:lower:]' '[:upper:]')_OK\"}],
      \"max_tokens\": 32,
      \"stream\": false
    }" 2>&1)
  if echo "$RESP" | grep -q "HELLO_$(echo $name | tr '[:lower:]' '[:upper:]')_OK"; then
    echo "  PASS"
    PASS=$((PASS+1))
  else
    echo "  FAIL — last 200 chars of response:"
    echo "$RESP" | tail -c 400 | sed 's/^/    /'
    FAIL=$((FAIL+1))
  fi
}

run_list_test() {
  local name="$1"
  local base="$2"
  local key="$3"
  echo ""
  echo "TEST: $name — list models"
  echo "  base: $base"
  if [ -z "$key" ] || [ "$key" = "REPLACE_ME" ]; then
    echo "  SKIP: no key configured"
    return 0
  fi
  RESP=$(curl -sS --max-time 15 "$base/models" \
    -H "Authorization: Bearer $key" 2>&1)
  COUNT=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "?")
  if [ "$COUNT" != "?" ] && [ "$COUNT" -gt 0 ] 2>/dev/null; then
    echo "  PASS — $COUNT models available"
    PASS=$((PASS+1))
  else
    echo "  FAIL"
    echo "$RESP" | tail -c 300 | sed 's/^/    /'
    FAIL=$((FAIL+1))
  fi
}

echo "=========================================="
echo " Claw Provider Smoke Tests"
echo "=========================================="

# Bitdeer
run_list_test "bitdeer" "${BITDEER_BASE_URL:-https://api-inference.bitdeer.ai/v1}" "${BITDEER_API_KEY:-}"
run_test "bitdeer" "${BITDEER_BASE_URL:-https://api-inference.bitdeer.ai/v1}" "${BITDEER_API_KEY:-}" \
  "${BITDEER_DEFAULT_MODEL:-meta/llama-3.1-70b-instruct}"

# NVIDIA NIM (test key #1)
run_list_test "nvidia_nim" "${NVIDIA_NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}" "${NVIDIA_NIM_KEY_1:-}"
run_test "nvidia_nim" "${NVIDIA_NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}" "${NVIDIA_NIM_KEY_1:-}" \
  "${NVIDIA_NIM_DEFAULT_MODEL:-meta/llama-3.1-405b-instruct}"

# If round-robin enabled, smoke test all keys
if [ "${NVIDIA_NIM_ROUND_ROBIN:-0}" = "1" ]; then
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    VAR="NVIDIA_NIM_KEY_$i"
    KEY="${!VAR:-}"
    [ -z "$KEY" ] && continue
    run_test "nvidia_nim_$i" "${NVIDIA_NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}" "$KEY" \
      "${NVIDIA_NIM_DEFAULT_MODEL:-meta/llama-3.1-405b-instruct}"
  done
fi

echo ""
echo "=========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
