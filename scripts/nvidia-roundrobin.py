#!/usr/bin/env python3
"""
scripts/nvidia-roundrobin.py

Lightweight local OpenAI-compatible proxy that load-balances across up to 12
NVIDIA NIM API keys. For each inbound request:
  - Picks the NIM key with the lowest recent request count
  - Forwards the request to https://integrate.api.nvidia.com/v1/...
  - Streams the response back to the caller unchanged

Usage:
  # 1. Set keys in .env or in your shell:
  export NVIDIA_NIM_KEY_1=nvapi-...
  export NVIDIA_NIM_KEY_2=nvapi-...
  ...
  # 2. Start the proxy:
  python3 scripts/nvidia-roundrobin.py --port 8765

  # 3. Point Claw at the local proxy:
  export OPENAI_BASE_URL="http://127.0.0.1:8765/v1"
  export OPENAI_API_KEY="roundrobin"   # any non-empty value; real key is picked per request
  claw --model "meta/llama-3.1-405b-instruct" prompt "hi"

Free-tier throughput: 12 keys * 40 RPM = 480 RPM aggregate.
"""
from __future__ import annotations
import argparse, http.server, json, os, sys, threading, time, urllib.request, urllib.error
from collections import deque
from http import HTTPStatus

NVIDIA_BASE = os.environ.get("NVIDIA_NIM_BASE_URL", "https://integrate.api.nvidia.com/v1").rstrip("/")
NIM_KEY_PREFIX = "NVIDIA_NIM_KEY_"


def load_keys() -> list[str]:
    keys = []
    for i in range(1, 13):
        v = os.environ.get(f"{NIM_KEY_PREFIX}{i}")
        if v:
            keys.append(v)
    return keys


# Per-key rolling request log for least-loaded selection
class KeyPool:
    def __init__(self, keys: list[str]):
        self.keys = keys
        self.lock = threading.Lock()
        # last_request_time per key (epoch seconds)
        self.last_used: dict[str, float] = {k: 0.0 for k in keys}
        # recent errors per key (for cooldown)
        self.recent_errors: dict[str, deque[float]] = {k: deque(maxlen=20) for k in keys}

    def pick(self) -> str | None:
        with self.lock:
            if not self.keys:
                return None
            now = time.time()
            # pick key with oldest last_used (least recently used)
            best = min(self.keys, key=lambda k: self.last_used[k])
            self.last_used[best] = now
            return best

    def record_error(self, key: str):
        with self.lock:
            self.recent_errors[key].append(time.time())


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    pool: KeyPool | None = None
    log_level: str = "info"

    def log_message(self, fmt, *args):
        if self.log_level == "quiet":
            return
        sys.stderr.write(f"[rr] {self.address_string()} {fmt % args}\n")

    def do_GET(self):
        if self.path == "/health":
            self._json(HTTPStatus.OK, {"ok": True, "keys_loaded": len(self.pool.keys)})
            return
        self._forward()

    def do_POST(self):
        self._forward()

    def _forward(self):
        if not self.pool or not self.pool.keys:
            self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "no NVIDIA_NIM_KEY_* env vars set"})
            return
        key = self.pool.pick()
        if not key:
            self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "no key available"})
            return

        # Build upstream URL
        url = NVIDIA_BASE + self.path
        # Read body
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""

        # Build request
        req = urllib.request.Request(url, data=body, method=self.command)
        # Strip incoming auth, set our chosen key
        for h in list(self.headers.keys()):
            if h.lower() in ("authorization", "host", "content-length"):
                continue
            req.add_header(h, self.headers[h])
        req.add_header("Authorization", f"Bearer {key}")
        if body:
            req.add_header("Content-Type", self.headers.get("Content-Type", "application/json"))

        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                payload = resp.read()
                self.send_response(resp.status)
                for h, v in resp.getheaders():
                    if h.lower() in ("transfer-encoding", "connection"):
                        continue
                    self.send_header(h, v)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
        except urllib.error.HTTPError as e:
            try:
                err_body = e.read()
            except Exception:
                err_body = b""
            self.pool.record_error(key)
            try:
                self.send_response(e.code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(err_body)))
                self.end_headers()
                self.wfile.write(err_body)
            except Exception:
                pass
        except Exception as e:
            self.pool.record_error(key)
            self._json(HTTPStatus.BAD_GATEWAY, {"error": f"upstream error: {e}"})

    def _json(self, status: int, body: dict):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main():
    ap = argparse.ArgumentParser(description="Round-robin OpenAI-compatible proxy for NVIDIA NIM keys")
    ap.add_argument("--port", type=int, default=8765, help="local port to listen on (default 8765)")
    ap.add_argument("--host", default="127.0.0.1", help="bind host (default 127.0.0.1)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    keys = load_keys()
    if not keys:
        print(f"ERROR: no keys found. Set env vars {NIM_KEY_PREFIX}1 .. {NIM_KEY_PREFIX}12", file=sys.stderr)
        sys.exit(1)

    ProxyHandler.pool = KeyPool(keys)
    ProxyHandler.log_level = "quiet" if args.quiet else "info"

    server = http.server.ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    print(f"[rr] round-robin proxy on http://{args.host}:{args.port}  →  {NVIDIA_BASE}")
    print(f"[rr]   {len(keys)} NVIDIA NIM keys loaded (40 RPM each = {40*len(keys)} RPM aggregate)")
    print(f"[rr]   health:    curl http://{args.host}:{args.port}/health")
    print(f"[rr]   usage:     export OPENAI_BASE_URL=http://{args.host}:{args.port}/v1")
    print(f"[rr]              export OPENAI_API_KEY=roundrobin")
    print(f"[rr]              claw --model 'meta/llama-3.1-405b-instruct' prompt 'hi'")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[rr] shutting down")
        server.shutdown()


if __name__ == "__main__":
    main()
