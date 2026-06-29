***REMOVED*** rodrigo-agent — agent instructions

IaC repo for a self-hosted AI agent runtime (Hermes + Headroom) on OVHcloud VPS running NixOS + k3s.

***REMOVED******REMOVED*** Architecture snapshot

```
Local: opencode → Headroom(:8787) → OpenRouter
VPS:   Caddy(host) → NodePort → k3s { Hermes Agent, Headroom proxy, Uptime Kuma }
```

Caddy runs as a NixOS service on the host (not k8s Ingress). It proxies to k8s services **via NodePort**. Don't use ClusterIP or k8s Ingress — Caddy does TLS termination. NodePort mappings: Hermes=30080, Headroom=30878, Uptime Kuma=30001.

k3s is installed with `--disable traefik --disable servicelb`. Traefik conflicts with Caddy.

***REMOVED******REMOVED*** Deploy order (exact)

```
tofu apply  →  nixos-infect  →  nixos-rebuild  →  ansible  →  kubectl apply
```

Use `./scripts/deploy.sh` with phase skip flags (`--skip-tofu`, `--skip-infect`, etc.). Do not skip phases or reorder.

**Pre-deploy:** create OVH Object Storage bucket for state first:
```bash
aws s3 mb s3://rodrigo-agent-tofu-state --endpoint-url https://s3.gra.io.REDACTED-OVH-DOMAIN
```

**After tofu:** VPS boots Debian 12. Convert to NixOS:
```bash
ssh root@$VPS_IP 'curl -sL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
  | NIX_CHANNEL=nixos-unstable bash'
```

**NixOS:** `rsync nix/` to `/etc/nixos/` on VPS, then `nixos-rebuild switch --flake /etc/nixos***REMOVED***agent`

**Ansible requires** Bitwarden unlocked before running. On the VPS:
```bash
bw login
bw unlock --raw > /root/.bw_session_token
```

The `secrets.yml` playbook reads from Bitwarden vault `rodrigo-agent` and writes to k8s Secrets + `/etc/restic/env` + `/etc/tailscale/authkey`.

**k8s manifests:** rsync to `/opt/k8s/` on VPS, then `kubectl apply -f /opt/k8s/namespace.yaml && kubectl apply -f /opt/k8s/hermes/` etc.

***REMOVED******REMOVED*** Key files

| Path | Purpose |
|------|---------|
| `tofu/main.tf` | OVH VPS + DNS A record (agent.REDACTED-DOMAIN) + S3 buckets. Uses `plan = []` list syntax, not block syntax |
| `tofu/variables.tf` | Uses `vps_display_name`, `vps_plan_code`, `vps_datacenter`, `ssh_public_key` + `vps_image_id` (both required together) |
| `nix/host.nix` | NixOS config: imports all modules, SSH hardened, user rodrigo, timezone REDACTED-TZ |
| `nix/caddy.nix` | Caddy proxies to localhost:NodePort (not k8s DNS). `reverse_proxy localhost:30080` for Hermes |
| `nix/k3s.nix` | k3s single-node server, traefik and servicelb disabled |
| `ansible/playbooks/secrets.yml` | Bitwarden → k8s Secret sync. Fetches 10 items, creates 4 secrets |
| `ansible/playbooks/deploy.yml` | kubectl apply from /opt/k8s/. Waits for rollout. Idempotent |
| `k8s/hermes/deployment.yaml` | Hermes: 1 replica, Recreate strategy (PVC), probes, 2CPU/4Gi limits |
| `k8s/headroom/service.yaml` | NodePort 30878 |
| `k8s/hermes/service.yaml` | NodePort 30080 |
| `scripts/deploy.sh` | Phase-aware deploy pipeline. Source of truth for deploy order |

***REMOVED******REMOVED*** Secrets (Bitwarden vault: `rodrigo-agent`)

10 items in vault. The `secrets.yml` playbook fetches them by name. See `ansible/vault.yml` for exact field names. Key items: OpenRouter API Key, Hermes Telegram/Discord tokens, Tailscale Auth Key, Restic password, OVH Object Storage keys.

***REMOVED******REMOVED*** Operations

- Status: `./scripts/deploy.sh status`
- Update workloads: `ansible-playbook -i inventory/hosts.yml playbooks/update.yml` (does pre/post restic backup + rollout restart)
- NixOS update: `ssh root@agent.REDACTED-DOMAIN 'nixos-rebuild switch --flake /etc/nixos***REMOVED***agent --upgrade'`
- Backup: systemd timer runs daily restic to OVH Object Storage. Retention 7d/4w/3m
- Manual backup: `ssh root@agent.REDACTED-DOMAIN 'systemctl start restic-backups-daily'`
- Destroy: `./scripts/deploy.sh destroy` (backup first!)

***REMOVED******REMOVED*** OCR (Baidu Unlimited-OCR on Lambda Cloud)

On-demand GPU OCR for images and PDFs. Managed via OpenTofu in `tofu/lambda.tf`.

***REMOVED******REMOVED******REMOVED*** CLI

```bash
./scripts/ocr.sh image.png          ***REMOVED*** OCR a single image
./scripts/ocr.sh document.pdf       ***REMOVED*** OCR a PDF (all pages)
./scripts/ocr.sh --status            ***REMOVED*** check if instance is alive
./scripts/ocr.sh --kill              ***REMOVED*** terminate GPU instance
```

First call auto-launches the GPU instance (~2 min). Subsequent calls reuse a warm
instance. Instance auto-terminates after 5 min idle (`--keep` to hold).

***REMOVED******REMOVED******REMOVED*** Hermes integration

Hermes has an `ocr` skill (`skills/ocr.md`). Send a file attachment on Discord
and say "extract text from this" — Hermes invokes the skill automatically.

***REMOVED******REMOVED******REMOVED*** Requirements

- `LAMBDA_CLOUD_API_KEY` env var
- SSH key in Lambda Cloud (managed via Tofu `tofu/lambda.tf`)
- GPU instance types: `gpu_1x_a10` (24GB, ~$0.60/hr) or `gpu_1x_l40s` (48GB, ~$0.90/hr)

***REMOVED******REMOVED*** Gotchas

- **OVH VPS resource** uses `plan = []` list syntax with `configuration` sub-blocks for datacenter + OS. Not block syntax. IPs are retrieved via `data.ovh_vps` data source, not from the resource directly.
- **SSH key on VPS** requires also setting `image_id` (OVH API constraint). If you skip both, VPS uses emailed root password.
- **NO Helmfile, Longhorn, or k8s Ingress** — this repo deliberately avoids them as overengineered for single-node.
- **Don't run `tofu apply` in CI** — OVH API rate-limits aggressively.
- **NixOS locale** uses `en_GB.UTF-8` default with `pt_BR.UTF-8` overrides for regional fields. This matches the user's nix-config convention.
- **Headroom runs in two places**: local machine (wraps opencode via `headroom wrap opencode`) and VPS (k3s deployment that Hermes routes through).
- **DNS propagation** on OVH is slow (hours). Use the raw IP for initial deploy.
- **Lambda GPU instance is NOT always running** — it's managed as an on-demand resource. Set `ocr_enabled = true` in Tofu before `apply`, or use `scripts/ocr.sh` which handles the lifecycle automatically.
