# Bitdeer AI Cloud + NVIDIA NIM Provider Setup

This guide wires **Bitdeer AI Cloud** and **NVIDIA NIM** as your `claw-code`
LLM backends — so you can run Claw against open models (Llama, Qwen, Kimi,
Mistral, DeepSeek, etc.) without an Anthropic API key.

Both providers expose an **OpenAI-compatible `/v1/chat/completions` endpoint**,
which Claw routes to automatically when you set `OPENAI_BASE_URL` + `OPENAI_API_KEY`.

---

## 1. Get your API keys

| Provider | Where to get a key | Free tier? | Notes |
|---|---|---|---|
| **Bitdeer AI Cloud** | https://www.bitdeer.ai/ → account → API keys | Sign-up credits | GPU-backed inference for many open models. Base URL: `https://api-inference.bitdeer.ai/v1` |
| **NVIDIA NIM** | https://build.nvidia.com/ → "Get API Key" | 1,000 free credits on signup, 40 RPM | 136+ open models on DGX Cloud. Base URL: `https://integrate.api.nvidia.com/v1` |

> 🔒 **Never paste API keys into chat, issues, or commits.** Store them in
> the encrypted vault of your agent runtime OR in a local `.env` file that's
> gitignored.

---

## 2. Configure Claw (3 ways, pick one)

### Option A — local `.env` file (recommended, gitignored)

Copy the template and edit:

```bash
cd clawcode
cp .env.example .env
nano .env   # paste your real keys
./scripts/load-env.sh   # exports them into the current shell
```

### Option B — interactive setup script (writes to local `settings.local.json`)

```bash
./scripts/setup-providers.sh
# Walks you through: Bitdeer key, NVIDIA NIM keys (up to 12 for round-robin),
# default model selection, then writes everything to .claw/settings.local.json
```

### Option C — shell exports (temporary, current session only)

```bash
export OPENAI_BASE_URL="https://integrate.api.nvidia.com/v1"
export OPENAI_API_KEY="nvapi-YOUR_KEY"
export CLAW_MODEL="nvidia/meta/llama-3.1-405b-instruct"
claw --model "nvidia/meta/llama-3.1-405b-instruct" prompt "hello"
```

---

## 3. Pick a model

### Recommended (good coding models, low cost)

| Provider | Model | Good for |
|---|---|---|
| NVIDIA NIM | `meta/llama-3.1-405b-instruct` | Best open coding model, large context |
| NVIDIA NIM | `qwen/qwen3-coder-480b-a35b-instruct` | Coder-specialist, 480B MoE |
| NVIDIA NIM | `moonshotai/kimi-k2-instruct` | Agentic, strong tool use |
| NVIDIA NIM | `mistralai/magistral-small-2506` | Reasoning + speed |
| Bitdeer | `seedream-5.0-lite` | Image gen (different endpoint shape) |

Browse all 136 NVIDIA NIM models:
```bash
curl -sS https://integrate.api.nvidia.com/v1/models \
  -H "Authorization: Bearer $NVIDIA_NIM_KEY_1" | jq '.data[].id'
```

---

## 4. Smoke test

```bash
# 1. Test the raw provider endpoint
./scripts/test-providers.sh

# 2. Test through Claw
./target/debug/claw --model "nvidia/meta/llama-3.1-405b-instruct" \
  prompt "Reply exactly: HELLO_FROM_NVIDIA_123"

# 3. Check Claw sees the right config
./target/debug/claw config env
./target/debug/claw status
```

Expected for step 2: response contains `HELLO_FROM_NVIDIA_123`.

---

## 5. Round-robin across multiple NVIDIA NIM keys

The free tier is 40 RPM per key. The setup script can write up to 12 keys
into a load-balancer pool. Claw rotates through them per request, giving
you up to 480 RPM (12 × 40).

To enable round-robin, run `./scripts/setup-providers.sh` and answer "yes"
when prompted for "Enable NVIDIA NIM round-robin?".

The pool is stored in `.claw/settings.local.json` under
`provider_routing.nvidia_nim.key_pool` and rotated by
`scripts/nvidia-roundrobin.py`.

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `401 Unauthorized` | Wrong/expired key | Regenerate at build.nvidia.com / bitdeer.ai |
| `404 model not found` | Model ID typo or deprecated | Run `./scripts/list-models.sh nvidia` |
| `429 rate limited` | Free-tier RPM hit | Add more NIM keys, or switch to Bitdeer |
| `claw doctor` says `no API key` | Env var not exported | `source .env` or rerun `load-env.sh` |
| Tool calls fail / JSON shape errors | Some non-Anthropic models return non-OpenAI tool-call shapes | Use `--no-tools` or pick a tool-call-strong model (Llama 3.1, Kimi K2, Qwen3-Coder) |

---

## 7. What's in this repo

| File | Purpose |
|---|---|
| `.env.example` | Template for local `.env` (no values, just keys) |
| `scripts/setup-providers.sh` | Interactive setup — writes `.claw/settings.local.json` |
| `scripts/load-env.sh` | `source` this to load `.env` into your shell |
| `scripts/test-providers.sh` | Smoke test all configured providers |
| `scripts/list-models.sh` | List available models from each provider |
| `scripts/nvidia-roundrobin.py` | Round-robin dispatcher for up to 12 NIM keys |
| `providers/bitdeer.json` | Provider profile — base URL, default model, model list |
| `providers/nvidia-nim.json` | Provider profile — base URL, default model, model list |
| `.claw/settings.example.json` | Example local settings file (committed as template) |
