***REMOVED*** rodrigo-agent

Infrastructure-as-code for my personal AI agent — a self-hosted runtime on OVHcloud.

***REMOVED******REMOVED*** Architecture

```
┌────────────────────────────────────────────────────────────┐
│ Local Machine (NixOS)                                      │
│                                                            │
│  opencode-go  ──→  Headroom (:8787)  ──→  OpenRouter API   │
│  (coding agent)    (token compression)    (LLM access)     │
│                                                            │
│  Headroom saves 60-95% on token costs.                     │
└────────────────────────┬───────────────────────────────────┘
                         │ Tailscale / HTTPS
                         ▼
┌────────────────────────────────────────────────────────────┐
│ OVHcloud VPS — NixOS + k3s                                 │
│                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Caddy        │  │  Tailscale   │  │  Firewall        │  │
│  │  (TLS proxy)  │  │  (VPN)       │  │  (locked down)   │  │
│  └──────┬───────┘  └──────────────┘  └──────────────────┘  │
│         │ proxied via localhost:NodePort                    │
│         ▼                                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  k3s (single-node Kubernetes)                        │   │
│  │                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │   │
│  │  │  Hermes      │  │  Headroom    │  │  Uptime    │  │   │
│  │  │  Agent       │  │  (proxy)     │  │  Kuma      │  │   │
│  │  │  (AI agent)  │  │  (compressor)│  │  (monitor) │  │   │
│  │  └──────┬───────┘  └──────┬───────┘  └────────────┘  │   │
│  │         │                  │                           │   │
│  │         ▼                  ▼                           │   │
│  │         OpenRouter API     OpenRouter API               │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Restic → OVH Object Storage (daily backups)         │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

***REMOVED******REMOVED*** Components

| Component | What It Does | Runs On |
|-----------|-------------|---------|
| **OpenTofu** | Provision OVHcloud VPS + DNS + Object Storage | Local machine |
| **NixOS** | Immutable OS with k3s, Caddy, Tailscale, firewall | VPS |
| **k3s** | Lightweight Kubernetes for service orchestration | VPS |
| **Hermes Agent** | Self-hosted AI agent with memory, skills, multi-platform gateways | k3s |
| **Headroom** | Token compression proxy (60-95% savings) | Both local + VPS |
| **Caddy** | Reverse proxy with automatic TLS | VPS (host level) |
| **Tailscale** | Secure overlay VPN for admin access | VPS |
| **Ansible** | Bootstrap, secrets from Bitwarden, deploy services | Local → VPS |
| **Uptime Kuma** | Uptime monitoring dashboard | k3s |
| **Restic** | Encrypted daily backups to OVH Object Storage | VPS (host level) |

***REMOVED******REMOVED*** Prerequisites

***REMOVED******REMOVED******REMOVED*** Accounts & Credentials
- [OVHcloud](https://ovhcloud.com) account — VPS + DNS + Object Storage
- [OpenRouter](https://openrouter.ai) API key — LLM access
- [Bitwarden](https://bitwarden.com) vault with secrets (see `ansible/vault.yml`)
- [Tailscale](https://tailscale.com) account — VPN
- Domain: `REDACTED-DOMAIN` managed by OVH DNS

***REMOVED******REMOVED******REMOVED*** Local Tools
- [OpenTofu](https://opentofu.org) ≥ 1.6
- [Ansible](https://docs.ansible.com) ≥ 9.0
- [Bitwarden CLI](https://bitwarden.com/help/cli/) (`bw`)
- [rsync](https://rsync.samba.org/)
- SSH key uploaded to OVH account

***REMOVED******REMOVED******REMOVED*** OVH API Credentials
```bash
export OVH_ENDPOINT=ovh-eu
export OVH_APPLICATION_KEY=your_app_key
export OVH_APPLICATION_SECRET=your_app_secret
export OVH_CONSUMER_KEY=your_consumer_key
export AWS_ACCESS_KEY_ID=your_s3_key
export AWS_SECRET_ACCESS_KEY=your_s3_secret
```

***REMOVED******REMOVED*** Directory Layout

```
rodrigo-agent/
├── tofu/              ***REMOVED*** OpenTofu: VPS, DNS, Object Storage
│   ├── main.tf        ***REMOVED*** Resources (VPS, DNS records, buckets)
│   ├── provider.tf    ***REMOVED*** OVH + AWS S3 providers
│   ├── variables.tf   ***REMOVED*** All configurable params
│   ├── backend.tf     ***REMOVED*** OVH Object Storage state backend
│   └── outputs.tf     ***REMOVED*** vps_ip, dns_fqdn, storage_endpoint
├── nix/               ***REMOVED*** NixOS flake for VPS
│   ├── flake.nix      ***REMOVED*** Flake entry point
│   ├── host.nix       ***REMOVED*** Main config (SSH, user, locale)
│   ├── k3s.nix        ***REMOVED*** k3s installation
│   ├── caddy.nix      ***REMOVED*** Caddy reverse proxy
│   ├── firewall.nix   ***REMOVED*** Firewall rules
│   ├── tailscale.nix  ***REMOVED*** Tailscale VPN
│   ├── backup.nix     ***REMOVED*** Restic daily backups
│   └── secrets.nix    ***REMOVED*** sops-nix config
├── ansible/           ***REMOVED*** Ansible automation
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── inventory/hosts.yml
│   ├── vault.yml      ***REMOVED*** Bitwarden vault template
│   └── playbooks/
│       ├── bootstrap.yml  ***REMOVED*** Initial server setup
│       ├── secrets.yml    ***REMOVED*** Bitwarden → k8s secrets sync
│       ├── deploy.yml     ***REMOVED*** Deploy workloads to k3s
│       └── update.yml     ***REMOVED*** Rolling update workflow
├── k8s/               ***REMOVED*** Kubernetes manifests
│   ├── namespace.yaml
│   ├── hermes/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── pvc.yaml
│   │   ├── configmap.yaml
│   │   └── hpa.yaml
│   ├── headroom/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── monitoring/
│       └── uptime-kuma.yaml
├── headroom/          ***REMOVED*** Headroom token compression configs
│   ├── README.md
│   ├── local-setup.md
│   ├── integration-guide.md
│   ├── local-config.yaml
│   └── server-config.yaml
└── scripts/
    └── deploy.sh      ***REMOVED*** Full deployment pipeline
```

***REMOVED******REMOVED*** Deploy

***REMOVED******REMOVED******REMOVED*** 1. Initial Provision

```bash
***REMOVED*** Use the deploy pipeline
export VPS_IP=""  ***REMOVED*** Will be set by tofu
./scripts/deploy.sh
```

This runs: `tofu apply` → `nixos-infect` → `nixos-rebuild` → `ansible-playbook` → `kubectl apply`

***REMOVED******REMOVED******REMOVED*** 2. Skip to Specific Phase

```bash
***REMOVED*** If you already have a VPS
./scripts/deploy.sh --skip-tofu

***REMOVED*** If NixOS is already running
./scripts/deploy.sh --skip-tofu --skip-infect
```

***REMOVED******REMOVED******REMOVED*** 3. Manual Deploy by Phase

```bash
***REMOVED*** Phase 1 — Provision VPS
cd tofu
tofu init
tofu plan
tofu apply
export VPS_IP=$(tofu output -raw vps_ip)

***REMOVED*** Phase 2 — Convert to NixOS
ssh root@$VPS_IP 'curl -sL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
  | NIX_CHANNEL=nixos-unstable bash'

***REMOVED*** Wait for reboot, then:
***REMOVED*** Phase 3 — Apply NixOS config
rsync -avz nix/ root@$VPS_IP:/etc/nixos/
ssh root@$VPS_IP 'nixos-rebuild switch --flake /etc/nixos***REMOVED***agent'

***REMOVED*** Phase 4 — Ansible + secrets
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap.yml
ansible-playbook -i inventory/hosts.yml playbooks/secrets.yml

***REMOVED*** Phase 5 — Deploy workloads
rsync -avz k8s/ root@$VPS_IP:/opt/k8s/
ssh root@$VPS_IP 'kubectl apply -f /opt/k8s/namespace.yaml'
ssh root@$VPS_IP 'kubectl apply -f /opt/k8s/hermes/'
ssh root@$VPS_IP 'kubectl apply -f /opt/k8s/headroom/'
ssh root@$VPS_IP 'kubectl apply -f /opt/k8s/monitoring/'
```

***REMOVED******REMOVED******REMOVED*** 4. Set Up Bitwarden Secrets

Create a Bitwarden vault named `rodrigo-agent` with these items:

| Field | Description |
|-------|-------------|
| `openrouter_api_key` | OpenRouter API key |
| `hermes_telegram_token` | Telegram bot token (from @BotFather) |
| `hermes_discord_token` | Discord bot token |
| `hermes_signal_number` | Signal phone number (if using Signal) |
| `hermes_whatsapp_number` | WhatsApp number (if using WhatsApp) |
| `hermes_webhook_secret` | Webhook secret for inbound messages |
| `tailscale_auth_key` | Tailscale pre-auth key (one-time use) |
| `caddy_admin_password` | Caddy admin endpoint password |
| `restic_password` | Restic backup encryption password |
| `ovh_access_key` | OVH Object Storage access key |
| `ovh_secret_key` | OVH Object Storage secret key |

See `ansible/vault.yml` for the template.

***REMOVED******REMOVED*** Daily Operations

***REMOVED******REMOVED******REMOVED*** Check Status
```bash
./scripts/deploy.sh status
```

***REMOVED******REMOVED******REMOVED*** Update Workloads
```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/update.yml
```

***REMOVED******REMOVED******REMOVED*** Update NixOS
```bash
ssh root@agent.REDACTED-DOMAIN 'nixos-rebuild switch --flake /etc/nixos***REMOVED***agent --upgrade'
```

***REMOVED******REMOVED******REMOVED*** View Logs
```bash
***REMOVED*** Hermes
ssh root@agent.REDACTED-DOMAIN 'kubectl logs -n hermes -l app=hermes-agent --tail=100'

***REMOVED*** Headroom dashboard
ssh root@agent.REDACTED-DOMAIN 'kubectl exec -n headroom deploy/headroom -- headroom dashboard'
```

***REMOVED******REMOVED******REMOVED*** Backups
- Automatic daily restic backups to OVH Object Storage
- Retention: 7 daily, 4 weekly, 3 monthly
- Backup includes: k3s data (PVCs), Hermes memory

```bash
***REMOVED*** Manual backup trigger
ssh root@agent.REDACTED-DOMAIN 'systemctl start restic-backups-daily'

***REMOVED*** List snapshots
ssh root@agent.REDACTED-DOMAIN 'restic -r s3:... snapshots'
```

***REMOVED******REMOVED******REMOVED*** Access VPS
```bash
***REMOVED*** Via Tailscale (recommended) — no exposed SSH port
ssh rodrigo@rodrigo-agent.tailnet-name.ts.net

***REMOVED*** Via public IP (if Tailscale is down)
ssh root@$(cd tofu && tofu output -raw vps_ip)
```

***REMOVED******REMOVED******REMOVED*** Destroy Everything
```bash
***REMOVED*** Make a final backup first!
./scripts/deploy.sh destroy
```

***REMOVED******REMOVED*** Local Headroom Setup

On your local machine (which already has opencode):

```bash
pip install "headroom-ai[all]"
headroom wrap opencode
headroom doctor
```

See `headroom/local-setup.md` for detailed instructions including systemd service setup and Nix Home Manager integration.

***REMOVED******REMOVED*** Integration with nix-config

This repo is standalone, but the NixOS configs can be integrated into your
existing `nix-config` flake:

1. Copy `nix/` → `~/Workspace/github.com/rbelem/nix-config/nixos/hosts/agent/`
2. Add to `flake.nix` as a new `nixosConfigurations.agent`
3. Import shared modules from `../../common`

***REMOVED******REMOVED*** Costs

| Service | Plan | Est. Monthly |
|---------|------|-------------|
| OVHcloud VPS | vps-value-2-4 (2 vCPU, 4GB RAM, 80GB NVMe) | ~€6 |
| OVH Object Storage | Pay-as-you-go (state + backups) | ~€1 |
| OpenRouter API | Pay-per-token | variable |
| Tailscale | Personal (free, 3 users/100 devices) | €0 |
| Domain REDACTED-DOMAIN | Already owned | €0 |
| **Total base** | | **~€7/month** |

LLM usage costs depend on how much you use Hermes and opencode. Headroom
reduces token costs by 60-95% on both local and VPS traffic.
