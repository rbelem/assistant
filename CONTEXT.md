***REMOVED*** rodrigo-agent — domain glossary

***REMOVED******REMOVED*** Host
The OVHcloud VPS that runs all services. Hostname: `agent-rodrigo`.

***REMOVED******REMOVED*** Platform services
OS-level services running directly on NixOS (not in k3s): Caddy, Tailscale, firewall, restic.

***REMOVED******REMOVED*** DNS scheme
Every service gets a flat subdomain on `REDACTED-DOMAIN` with a public A record pointing to the VPS IP. Domain registered at Porkbun. DNS records managed via `marcfrederick/porkbun` OpenTofu provider.

TLS via Caddy Let's Encrypt using **DNS-01 challenge** with Porkbun API — wildcard cert `*.REDACTED-DOMAIN` covers all current and future services. No port 80 dependency. Access control enforced by Caddy IP allowlist for non-public services.

| Service | Domain | Access |
|---------|--------|--------|
| Hermes  | `hermes.REDACTED-DOMAIN` | Public |
| Status  | `status.REDACTED-DOMAIN` | Public |
| n8n     | `n8n.REDACTED-DOMAIN` | Tailscale-gated |
| Zitadel | `auth.REDACTED-DOMAIN` | Tailscale-gated |

***REMOVED******REMOVED*** Hermes
Self-hosted AI agent by Nous Research. Agentic tasks: memory, skills, scheduling, multi-platform gateways. Initial gateway: **Discord only** (no Telegram, Signal, or Matrix at launch). Runs in k3s namespace `hermes`. LLM calls route through Headroom proxy via `OPENROUTER_BASE_URL`. Default model: **DeepSeek V4 Flash** (`deepseek/deepseek-v4-flash`) via OpenRouter.

***REMOVED******REMOVED*** Headroom
Token compression proxy for LLM calls. Runs as an internal ClusterIP-only service inside the `hermes` namespace — consumed by Hermes via `OPENROUTER_BASE_URL`. No external exposure.

***REMOVED******REMOVED*** n8n
Self-hosted workflow automation (node-based编排, 400+ integrations). Additive to Hermes — handles external API integrations, notifications, data pipelines while Hermes handles agentic tasks. Runs in k3s namespace `n8n`. Deployed via Helm chart (managed through Helmfile). 2Gi PVC for workflow data. PostgreSQL via shared Bitnami chart (5Gi PVC, shared with Zitadel). Encryption key stored in Bitwarden vault. Authenticated via Zitadel OIDC.

***REMOVED******REMOVED*** Zitadel
Identity provider (Go-based, OIDC/OAuth2, WebAuthn). Provides auth for n8n and future expansion to professional multi-user use. ~500MB total with DB. Deployed via Helmfile in k3s, namespace `auth`. Shares PostgreSQL with n8n (Bitnami chart, separate database, database created via Helm hook job). Masterkey and admin password stored in Bitwarden vault.

***REMOVED******REMOVED*** Uptime Kuma
Uptime monitoring dashboard. Runs in k3s namespace `monitoring`.

***REMOVED******REMOVED*** PostgreSQL
Database for n8n and Zitadel (shared Bitnami Helm chart, separate databases). 5Gi PVC via local-path storage class. Hermes uses local file-based memory.

***REMOVED******REMOVED*** Helmfile
Declarative Helm release manager. Manages Bitnami PostgreSQL, n8n, and Zitadel Helm releases. Config in `k8s/helmfile.yaml` with values in `k8s/helm/`. Used alongside raw `kubectl apply` for non-Helm manifests (Hermes, Headroom, Uptime Kuma in `k8s/manifests/`).

***REMOVED******REMOVED*** OCR
Text extraction from images/PDFs using Baidu Unlimited-OCR model deployed on Lambda Cloud GPU instances (`gpu_1x_a10` or `gpu_1x_l40s`). On-demand lifecycle: Tofu provisions the instance, `scripts/ocr.sh` manages the full flow (launch → deploy model → OCR → return text → terminate). Hermes can invoke via the `ocr` skill. OpenAI-compatible API via vLLM Docker image `vllm/vllm-openai:unlimited-ocr`. Requires `LAMBDA_CLOUD_API_KEY`.
