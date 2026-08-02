#!/usr/bin/env bash
# scripts/setup-providers.sh
# Interactive setup: writes Bitdeer + NVIDIA NIM config to .claw/settings.local.json
# Safe to re-run — preserves existing settings.

set -euo pipefail

# Locate the clawcode repo root (script lives at <root>/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

CLAW_LOCAL_DIR=".claw"
CLAW_LOCAL_FILE="$CLAW_LOCAL_DIR/settings.local.json"

# Ensure .gitignore covers the local file
grep -qxF '.claw/settings.local.json' .gitignore 2>/dev/null || \
  echo '.claw/settings.local.json' >> .gitignore

mkdir -p "$CLAW_LOCAL_DIR"

# Load existing settings if any
if [ -f "$CLAW_LOCAL_FILE" ]; then
  echo "==> Found existing $CLAW_LOCAL_FILE — preserving existing keys"
  EXISTING=$(cat "$CLAW_LOCAL_FILE")
else
  EXISTING='{}'
fi

echo ""
echo "=========================================="
echo " Claw Provider Setup"
echo " Bitdeer AI Cloud + NVIDIA NIM"
echo "=========================================="
echo ""

# --- Bitdeer ---
echo ">> Bitdeer AI Cloud"
echo "   Get a key at: https://www.bitdeer.ai/"
read -r -p "   Bitdeer API key (leave blank to skip): " BITDEER_KEY
BITDEER_KEY=${BITDEER_KEY:-}

if [ -n "$BITDEER_KEY" ]; then
  BITDEER_DEFAULT_MODEL=${BITDEER_DEFAULT_MODEL:-meta/llama-3.1-70b-instruct}
  read -r -p "   Bitdeer default model [$BITDEER_DEFAULT_MODEL]: " BITDEER_MODEL
  BITDEER_MODEL=${BITDEER_MODEL:-$BITDEER_DEFAULT_MODEL}
fi

echo ""

# --- NVIDIA NIM ---
echo ">> NVIDIA NIM (https://build.nvidia.com/)"
echo "   You can add up to 12 keys for round-robin (40 RPM each = 480 RPM total)"
echo "   Press enter on a blank key to stop adding more."

NVIDIA_KEYS=()
for i in $(seq 1 12); do
  VAR_NAME="NVIDIA_NIM_KEY_$i"
  # Check env first
  if [ -n "${!VAR_NAME:-}" ]; then
    NVIDIA_KEYS+=("${!VAR_NAME}")
    echo "   Using env $VAR_NAME"
    continue
  fi
  # Prompt
  read -r -p "   Key #$i (blank to stop): " KEY_VAL
  if [ -z "$KEY_VAL" ]; then
    break
  fi
  NVIDIA_KEYS+=("$KEY_VAL")
done

NVIDIA_COUNT=${#NVIDIA_KEYS[@]}
NVIDIA_DEFAULT_MODEL=${NVIDIA_NIM_DEFAULT_MODEL:-meta/llama-3.1-405b-instruct}
if [ "$NVIDIA_COUNT" -gt 0 ]; then
  read -r -p "   NVIDIA default model [$NVIDIA_DEFAULT_MODEL]: " NVIDIA_MODEL
  NVIDIA_MODEL=${NVIDIA_MODEL:-$NVIDIA_DEFAULT_MODEL}
fi

echo ""

# --- Default provider ---
if [ "$NVIDIA_COUNT" -gt 0 ] && [ -n "$BITDEER_KEY" ]; then
  read -r -p ">> Default provider (nvidia|bitdeer) [nvidia]: " DEFAULT_PROVIDER
  DEFAULT_PROVIDER=${DEFAULT_PROVIDER:-nvidia}
elif [ "$NVIDIA_COUNT" -gt 0 ]; then
  DEFAULT_PROVIDER="nvidia"
else
  DEFAULT_PROVIDER="bitdeer"
fi

# --- Round-robin for NIM ---
ENABLE_RR="false"
if [ "$NVIDIA_COUNT" -gt 1 ]; then
  read -r -p ">> Enable NVIDIA NIM round-robin across $NVIDIA_COUNT keys? [Y/n]: " RR_ANSWER
  RR_ANSWER=${RR_ANSWER:-Y}
  case "$RR_ANSWER" in
    [Yy]*) ENABLE_RR="true" ;;
  esac
fi

# --- Write settings.local.json ---
echo ""
echo "==> Writing $CLAW_LOCAL_FILE"

python3 - "$CLAW_LOCAL_FILE" "$EXISTING" \
  "$BITDEER_KEY" "$BITDEER_MODEL" \
  "$NVIDIA_COUNT" "$NVIDIA_MODEL" "$DEFAULT_PROVIDER" "$ENABLE_RR" \
  <<'PYEOF'
import json, os, sys
out_path, existing_json, bitdeer_key, bitdeer_model, \
    n_count, n_model, default_provider, enable_rr = sys.argv[1:]

try:
    cfg = json.loads(existing_json) if existing_json.strip() else {}
except Exception:
    cfg = {}

# env block
cfg.setdefault("env", {})
if bitdeer_key:
    cfg["env"]["BITDEER_API_KEY"] = bitdeer_key
    cfg["env"]["BITDEER_BASE_URL"] = "https://api-inference.bitdeer.ai/v1"

# provider_routing block
pr = cfg.setdefault("provider_routing", {})
pr["default_provider"] = default_provider
providers = pr.setdefault("providers", {})

if bitdeer_key:
    providers["bitdeer"] = {
        "type": "openai_compatible",
        "base_url": "https://api-inference.bitdeer.ai/v1",
        "env_key": "BITDEER_API_KEY",
        "default_model": bitdeer_model,
    }

if int(n_count) > 0:
    providers["nvidia"] = {
        "type": "openai_compatible",
        "base_url": "https://integrate.api.nvidia.com/v1",
        "env_key": "NVIDIA_NIM_KEY_1",
        "default_model": n_model,
        "models": [
            "meta/llama-3.1-405b-instruct",
            "meta/llama-3.1-70b-instruct",
            "qwen/qwen3-coder-480b-a35b-instruct",
            "moonshotai/kimi-k2-instruct",
            "mistralai/magistral-small-2506",
            "deepseek-ai/deepseek-r1",
            "nvidia/llama-3.1-nemoguard-8b-content-safety",
        ],
    }
    pr["nvidia_nim"] = {
        "key_pool_enabled": enable_rr == "true",
        "keys_env_prefix": "NVIDIA_NIM_KEY_",
        "rotator_script": "scripts/nvidia-roundrobin.py",
    }
    # Map OPENAI_* to NIM as the default runtime
    cfg["env"]["OPENAI_BASE_URL"] = "https://integrate.api.nvidia.com/v1"
    cfg["env"]["OPENAI_API_KEY"] = "$NVIDIA_NIM_KEY_1"  # placeholder; rotated by RR script
    cfg["model"] = f"nvidia/{n_model}"

# permissions defaults — keep the user's existing if any
cfg.setdefault("permissions", {
    "default_mode": "acceptEdits",
    "allow": [],
    "deny": [],
    "ask": [],
})

with open(out_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"   wrote {out_path}  ({os.path.getsize(out_path)} bytes)")
PYEOF

# --- Write .env if user wants ---
if [ "$NVIDIA_COUNT" -gt 0 ] || [ -n "$BITDEER_KEY" ]; then
  if [ ! -f .env ]; then
    cp .env.example .env
    echo "==> Created .env from .env.example (edit it to add the rest of your NIM keys)"
  else
    echo "==> .env already exists — leaving it alone"
  fi
fi

echo ""
echo "=========================================="
echo " Done!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Review:    cat $CLAW_LOCAL_FILE"
echo "  2. Test:      ./scripts/test-providers.sh"
echo "  3. Run Claw:  ./target/debug/claw --model \"$NVIDIA_MODEL\" prompt 'hello'"
echo ""
echo "Tip: For round-robin across multiple NIM keys, run the app through"
echo "     scripts/nvidia-roundrobin.py which dispatches to a free key per request."
