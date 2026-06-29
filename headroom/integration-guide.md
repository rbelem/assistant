***REMOVED*** Headroom Integration Guide

How the two deployments work, how to verify compression, and how to troubleshoot.

***REMOVED******REMOVED*** Architecture Overview

```
LOCAL MACHINE                          VPS (k3s)
┌─────────────┐                     ┌──────────────┐
│  opencode   │                     │ Hermes Agent  │
│  (client)   │                     │  (client)     │
└──────┬──────┘                     └──────┬────────┘
       │                                   │
       ▼                                   ▼
┌─────────────┐                     ┌──────────────┐
│  Headroom   │ :8787               │  Headroom    │ :8787
│  (local)    │ 127.0.0.1           │  (proxy)     │ 0.0.0.0
└──────┬──────┘                     └──────┬────────┘
       │                                   │
       ▼                                   ▼
┌─────────────┐                     ┌──────────────┐
│  OpenRouter │                     │  OpenRouter  │
│  (upstream) │                     │  (upstream)  │
└─────────────┘                     └──────────────┘
```

***REMOVED******REMOVED*** How opencode Routes Through Headroom (Local)

When you run `headroom wrap opencode`, it does two things:

1. Starts the Headroom proxy on `127.0.0.1:8787`
2. Patches opencode's config to point `base_url` at `http://127.0.0.1:8787` instead
   of `https://openrouter.ai/api/v1`

opencode thinks it's talking to OpenRouter. It's actually talking to Headroom.
Headroom compresses the request, forwards it to OpenRouter, compresses the response,
and sends it back.

To verify the config was patched:

```bash
***REMOVED*** Check opencode's effective config
opencode config show

***REMOVED*** The base_url should point to localhost:8787
```

***REMOVED******REMOVED*** How Hermes Agent Uses Headroom (VPS)

Hermes doesn't need `headroom wrap`. Instead, configure its `base_url` directly:

```yaml
***REMOVED*** In Hermes's LLM config
llm:
  base_url: http://headroom-proxy:8787   ***REMOVED*** k8s service name, or localhost if same pod
  api_key: ${OPENROUTER_API_KEY}
  model: openrouter/your-model
```

The Headroom proxy is deployed as a k8s Deployment/Service. Hermes routes through
it automatically. No code changes to Hermes needed.

***REMOVED******REMOVED*** Verify Compression Is Working

***REMOVED******REMOVED******REMOVED*** Quick check

```bash
***REMOVED*** Run from either machine
headroom doctor
```

This checks proxy health, upstream connectivity, and compressor status.

***REMOVED******REMOVED******REMOVED*** Live stats

```bash
headroom perf
```

Shows per-request compression ratios. You should see something like:

```
REQUEST          INPUT   OUTPUT   SAVED
chat/completion  12,400  3,100    75%
chat/completion   8,200  2,050    75%
chat/completion  45,000  9,000    80%
```

***REMOVED******REMOVED******REMOVED*** Dashboard

```bash
headroom dashboard
```

Opens a web UI with real-time graphs of compression ratios, token savings,
per-compressor breakdowns, and memory usage.

***REMOVED******REMOVED******REMOVED*** Check specific compressor

```bash
***REMOVED*** See which compressors are active
headroom compressors list

***REMOVED*** Test a specific compressor on a file
headroom compress --compressor code --input ./some-file.py
```

***REMOVED******REMOVED*** Troubleshooting

***REMOVED******REMOVED******REMOVED*** Proxy won't start — port in use

```bash
***REMOVED*** Check what's on 8787
lsof -i :8787

***REMOVED*** Or change the port in local-config.yaml / server-config.yaml
```

***REMOVED******REMOVED******REMOVED*** opencode not routing through proxy

```bash
***REMOVED*** Verify the config was patched
opencode config show | grep base_url

***REMOVED*** If it still points to OpenRouter directly, re-run wrap
headroom wrap opencode

***REMOVED*** Or manually set it:
***REMOVED*** In opencode's config, change base_url to http://127.0.0.1:8787
```

***REMOVED******REMOVED******REMOVED*** Compression ratio is low (< 30%)

- Check which compressor is handling your content: `headroom perf --verbose`
- Code-heavy workloads should see 60-80% with `code: true`
- If mostly short prompts, compression will naturally be lower
- Try increasing `level` in the config (e.g., 5 → 7)

***REMOVED******REMOVED******REMOVED*** Compression is too aggressive / losing info

- Decrease `level` (e.g., 7 → 5)
- Disable specific compressors: set `image: false` or `text: false`
- Use CCR to retrieve originals: `headroom ccr get <request-id>`

***REMOVED******REMOVED******REMOVED*** Memory store issues

```bash
***REMOVED*** Check memory status
headroom memory status

***REMOVED*** Reset the memory store (loses learned context)
headroom memory reset

***REMOVED*** Inspect stored entries
headroom memory list
```

***REMOVED******REMOVED******REMOVED*** VPS proxy not reachable from Hermes

```bash
***REMOVED*** From the Hermes pod/container, test connectivity
curl http://headroom-proxy:8787/health

***REMOVED*** Check the k8s service exists and has endpoints
kubectl get svc headroom-proxy
kubectl get endpoints headroom-proxy

***REMOVED*** Check proxy logs
kubectl logs -l app=headroom-proxy --tail=50
```

***REMOVED******REMOVED*** Reading Dashboard Stats

The `headroom dashboard` shows:

- **Input tokens saved** — total tokens compressed away from requests
- **Output tokens saved** — tokens saved via output shaping
- **Compression ratio** — percentage reduction (higher = better)
- **Per-compressor breakdown** — which compressor (code/json/text/image) is doing
  the most work
- **Memory hits** — how often cross-agent memory injected relevant context
- **CCR cache stats** — cache hit rate, stored originals, evictions
- **Request timeline** — per-request compression over time

A healthy setup shows 60-80% compression on code-heavy workloads and 40-60%
on mixed workloads. If you're consistently below 30%, check compressor config.
