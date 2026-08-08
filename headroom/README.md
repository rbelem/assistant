***REMOVED*** Headroom — Token Compression Layer

Headroom compresses everything your AI agent reads before it reaches the LLM.
Tool outputs, logs, files, conversation history — all of it gets crushed down,
saving 60–95% of tokens on every request.

***REMOVED******REMOVED*** How It Works

Headroom sits between your coding agent and the LLM API as a transparent proxy.
It uses AST-aware code compression, JSON crushing, prose summarization, and image
compression to reduce token counts without losing semantic meaning.

***REMOVED******REMOVED*** Supported Agents

Works with any OpenAI-API-compatible agent:

- **opencode** (opencode-go/opencode-zen)
- Claude Code / Claude Desktop
- GitHub Copilot
- Cursor
- Zet Agent
- Any custom agent using the OpenAI chat completions API

***REMOVED******REMOVED*** Deployment Modes

***REMOVED******REMOVED******REMOVED*** Local — wrap opencode directly

```bash
headroom wrap opencode
```

This starts a local proxy on `127.0.0.1:8787` and reconfigures opencode to route
through it. No code changes needed — it patches the config automatically.

***REMOVED******REMOVED******REMOVED*** VPS — run as a standalone proxy

Deploy the proxy alongside your agent (e.g., Zet on k3s). Point the agent's
`base_url` to the proxy instead of the upstream LLM API.

See [`local-setup.md`](local-setup.md) and [`integration-guide.md`](integration-guide.md)
for full instructions.

***REMOVED******REMOVED*** Install

```bash
***REMOVED*** Python (recommended — includes all compressors)
pip install "headroom-ai[all]"

***REMOVED*** Or via npm
npm install headroom-ai
```

***REMOVED******REMOVED*** Quick Start

```bash
***REMOVED*** 1. Install
pip install "headroom-ai[all]"

***REMOVED*** 2. Wrap your agent
headroom wrap opencode

***REMOVED*** 3. Verify it's working
headroom doctor
headroom perf

***REMOVED*** 4. View live stats
headroom dashboard
```

***REMOVED******REMOVED*** Config Files

| File | Purpose |
|---|---|
| [`local-config.yaml`](local-config.yaml) | Proxy config for local machine (wrapping opencode) |
| [`server-config.yaml`](server-config.yaml) | Proxy config for VPS (Zet Agent on k3s) |

***REMOVED******REMOVED*** Key Features

- **Code compression** — AST-aware; preserves structure, strips redundancy
- **JSON crushing** — smart reduction of verbose JSON payloads
- **Prose compression** — summarizes long text while keeping key info
- **Image compression** — 40–90% reduction on vision inputs
- **Output shaping** — reduces LLM output verbosity on routine turns
- **Cross-agent memory** — shared context between multiple agents
- **CCR (reversible compression)** — cache originals for later retrieval
- **Auto-learning** — learns from past sessions to improve compression
