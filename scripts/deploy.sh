#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# assistant deployment pipeline
# ─────────────────────────────────────────────────────────────
# Order: tofu → nixos-infect → nixos-rebuild → ansible → helmfile → kubectl
#
# Prerequisites:
#   - OVH API credentials (OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY)
#   - OVH Object Storage credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#   - Porkbun API credentials (PORKBUN_API_KEY, PORKBUN_SECRET_API_KEY)
#   - Lambda Cloud API key (LAMBDA_CLOUD_API_KEY) for OCR GPU instances
#   - SSH key uploaded to OVH account & Lambda Cloud
#   - Bitwarden CLI installed and logged in
#
# Usage:
#   ./deploy.sh                    ***REMOVED*** full deploy (prompts before destructive steps)
#   ./deploy.sh --skip-tofu        ***REMOVED*** skip provisioning, go to nixos-infect
#   ./deploy.sh --skip-infect      ***REMOVED*** skip nixos-infect, go to nixos-rebuild
#   ./deploy.sh --skip-nixos       ***REMOVED*** skip nixos-rebuild, go to ansible
#   ./deploy.sh --skip-ansible     ***REMOVED*** skip ansible, go to helmfile
#   ./deploy.sh --skip-helmfile    ***REMOVED*** skip helmfile, go to kubectl
#   ./deploy.sh --skip-tofu --skip-infect --skip-nixos --skip-ansible  ***REMOVED*** helmfile + kubectl only
#   ./deploy.sh status             ***REMOVED*** show deployment status
#   ./deploy.sh destroy            ***REMOVED*** tear everything down
# ─────────────────────────────────────────────────────────────
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Config ──────────────────────────────────────────────────
VPS_IP="${VPS_IP:-}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
K8S_MANIFESTS="$DIR/k8s/manifests"
PLAYBOOKS="$DIR/ansible/playbooks"
INVENTORY="$DIR/ansible/inventory/hosts.yml"
VERBOSE="${VERBOSE:-0}"

# Allowlist of variables passed to envsubst when rendering *.tmpl files.
# This prevents $HOME, $USER, $PWD, etc. from leaking into committed files.
RENDER_VARS='$VPS_HOST $VPS_SSH_USER $VPS_SSH_PORT $DOMAIN $SUBDOMAINS_JSON $PROJECT_NAME $VPS_PLAN_CODE $DATACENTER'
HELMFILE_DIR="$DIR/k8s"
HELMFILE_BIN="${HELMFILE_BIN:-helmfile}"

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }
step()  { echo; echo -e "${BLUE}═══ $* ═══${NC}"; }

# ── Helpers ─────────────────────────────────────────────────
prompt_confirm() {
  echo -en "${YELLOW}Continue? [y/N]${NC} "
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]] || { err "Aborted."; exit 1; }
}

run_ssh() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$SSH_USER@$VPS_IP" "$@"
}

# ── Phases ──────────────────────────────────────────────────

phase_inventory_render() {
  step "preflight — fetch vault + render templates"

  if ! command -v envsubst &>/dev/null; then
    err "envsubst (gettext) is required to render *.tmpl files"
    exit 1
  fi

  ***REMOVED*** Pull deployment config from Bitwarden into .rendered/vault.env.
  "$DIR/scripts/fetch_vault.sh"

  ***REMOVED*** Source only the vault-generated exports. set -a auto-exports every variable
  ***REMOVED*** defined while it is active, so envsubst can see the allowlisted names.
  set -a
  ***REMOVED*** shellcheck source=.rendered/vault.env
  . "$DIR/.rendered/vault.env"
  set +a

  ***REMOVED*** Export the allowlist explicitly; envsubst uses the current environment.
  ***REMOVED*** Any new name added to RENDER_VARS above must also be exported here.
  export VPS_HOST VPS_SSH_USER VPS_SSH_PORT DOMAIN SUBDOMAINS_JSON PROJECT_NAME VPS_PLAN_CODE DATACENTER

  ***REMOVED*** Fall back to vault-derived host when VPS_IP is not already set (e.g.
  ***REMOVED*** --skip-tofu runs). This keeps run_ssh() working across all phases.
  VPS_IP="${VPS_IP:-$VPS_HOST}"
  export VPS_IP

  ***REMOVED*** Also honor vault-derived SSH user unless the caller overrode it.
  SSH_USER="${SSH_USER:-$VPS_SSH_USER}"
  export SSH_USER

  ***REMOVED*** Render every *.tmpl outside .rendered/ in-place.
  local tpl out
  while IFS= read -r -d '' tpl; do
    out="${tpl%.tmpl}"
    envsubst "$RENDER_VARS" < "$tpl" > "$out"
  done < <(find "$DIR" -name '*.tmpl' -not -path "$DIR/.rendered/*" -print0)

  ok "Ansible inventory rendered from vault."
}

phase_tofu() {
  step "1/6 — Provision VPS with OpenTofu"
  cd "$DIR/tofu"

  info "Initializing OpenTofu..."
  tofu init

  info "Planning infrastructure..."
  tofu plan -out=plan.out

  echo -e "${YELLOW}Review the plan above.${NC}"
  prompt_confirm

  info "Applying..."
  tofu apply plan.out
  ok "VPS provisioned."

  ***REMOVED*** Capture VPS IP
  VPS_IP=$(tofu output -raw vps_ip)
  info "VPS IP: $VPS_IP"

  ***REMOVED*** Inventory is now rendered from Bitwarden vault by phase_inventory_render()
  ***REMOVED*** before the Ansible phase runs. VPS_IP is captured above for SSH use.
}

phase_infect() {
  step "2/6 — Convert Debian to NixOS (nixos-infect)"
  if [[ -z "$VPS_IP" ]]; then
    err "VPS_IP not set. Run phase_tofu first or export VPS_IP."
    exit 1
  fi

  info "Waiting for SSH to be available..."
  for i in $(seq 1 30); do
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
         -o ConnectTimeout=5 "$SSH_USER@$VPS_IP" "echo ready" 2>/dev/null; then
      ok "SSH available."
      break
    fi
    sleep 5
  done

  warn "This will DESTROY the current OS and install NixOS."
  warn "Make sure you have console/rescue access to this VPS."
  prompt_confirm

  info "Running nixos-infect..."
  ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" \
    'curl -sL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
    | NIX_CHANNEL=nixos-unstable bash'

  ok "NixOS installed. The VPS will reboot."
  info "Waiting for reboot and SSH to come back..."
  sleep 30
  for i in $(seq 1 30); do
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
         -o ConnectTimeout=5 "$SSH_USER@$VPS_IP" "echo ready" 2>/dev/null; then
      ok "VPS back online with NixOS."
      break
    fi
    sleep 10
  done
}

phase_nixos() {
  step "3/6 — Apply NixOS configuration"
  if [[ -z "$VPS_IP" ]]; then
    err "VPS_IP not set."
    exit 1
  fi

  NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$HOME/Workspace/github.com/rbelem/nix-config}"
  if [[ ! -d "$NIX_CONFIG_DIR" ]]; then
    err "nix-config repo not found at $NIX_CONFIG_DIR"
    err "Set NIX_CONFIG_DIR to the path of the nix-config repo."
    exit 1
  fi

  info "Building and switching NixOS configuration from $NIX_CONFIG_DIR..."
  nixos-rebuild switch \
    --flake "path:$NIX_CONFIG_DIR#agent" \
    --target-host "$SSH_USER@$VPS_IP" \
    --use-substitutes

  ok "NixOS configuration applied (k3s, Caddy, Tailscale, firewall)."
}

phase_ansible() {
  step "4/6 — Configure services with Ansible + Bitwarden"
  cd "$DIR/ansible"

  ***REMOVED*** Ensure Bitwarden is logged in
  if ! bw status 2>/dev/null | grep -q '"status":"unlocked"'; then
    info "Bitwarden session required."
    export BW_SESSION=$(bw login --check 2>&1 | grep -o 'BW_SESSION="[^"]*"' | cut -d'"' -f2)
    if [[ -z "${BW_SESSION:-}" ]]; then
      info "Logging into Bitwarden..."
      eval $(bw login | grep 'export BW_SESSION')
    fi
  fi

  info "Running bootstrap playbook..."
  ansible-playbook -i "$INVENTORY" "$PLAYBOOKS/bootstrap.yml"

  info "Running secrets sync playbook..."
  ansible-playbook -i "$INVENTORY" "$PLAYBOOKS/secrets.yml"

  ok "Ansible configuration complete."
}

phase_helmfile() {
  step "5/6 — Deploy Helm releases (Postgres, n8n, Zitadel)"
  if [[ -z "$VPS_IP" ]]; then
    err "VPS_IP not set."
    exit 1
  fi

  if ! command -v "$HELMFILE_BIN" &>/dev/null; then
    ***REMOVED*** Helmfile should be installed on the VPS via NixOS packages
    info "Helmfile not found locally. Using helmfile on VPS..."
    HELMFILE_CMD="run_ssh"
    HELMFILE_DIR_REMOTE="/opt/k8s"
  else
    HELMFILE_CMD="bash -c"
    HELMFILE_DIR_REMOTE="$HELMFILE_DIR"
  fi

  info "Copying Helm values to VPS..."
  run_ssh "mkdir -p $HELMFILE_DIR_REMOTE/helm"
  rsync -avz -e "ssh -i $SSH_KEY" \
    "$HELMFILE_DIR/helmfile.yaml" "$SSH_USER@$VPS_IP:$HELMFILE_DIR_REMOTE/"
  rsync -avz -e "ssh -i $SSH_KEY" \
    "$HELMFILE_DIR/helm/" "$SSH_USER@$VPS_IP:$HELMFILE_DIR_REMOTE/helm/"

  info "Running helmfile sync..."
  run_ssh "cd $HELMFILE_DIR_REMOTE && helmfile sync"

  ok "Helm releases deployed."
}

phase_kubectl() {
  step "6/6 — Deploy raw manifests to k3s"
  if [[ -z "$VPS_IP" ]]; then
    err "VPS_IP not set."
    exit 1
  fi

  info "Copying k8s manifests to VPS..."
  run_ssh "mkdir -p /opt/k8s/manifests"
  rsync -avz -e "ssh -i $SSH_KEY" \
    "$K8S_MANIFESTS/" "$SSH_USER@$VPS_IP:/opt/k8s/manifests/"

  info "Deploying Hermes Agent..."
  run_ssh "kubectl apply -f /opt/k8s/manifests/hermes/"

  info "Deploying Headroom proxy..."
  run_ssh "kubectl apply -f /opt/k8s/manifests/headroom/"

  info "Deploying Uptime Kuma..."
  run_ssh "kubectl apply -f /opt/k8s/manifests/monitoring/"

  info "Waiting for pods to become ready..."
  run_ssh "
    kubectl wait --for=condition=Ready pods --all --all-namespaces --timeout=180s || true
    echo '=== Pod Status ==='
    kubectl get pods --all-namespaces
    echo '=== Services ==='
    kubectl get svc --all-namespaces
  "

  ok "All workloads deployed."
}

phase_status() {
  step "Deployment Status"
  if [[ -z "$VPS_IP" ]]; then
    if [[ -f "$DIR/tofu/.terraform/terraform.tfstate" ]] || [[ -f "$DIR/tofu/terraform.tfstate" ]]; then
      cd "$DIR/tofu"
      VPS_IP=$(tofu output -raw vps_ip 2>/dev/null || echo "")
    fi
  fi

  if [[ -n "$VPS_IP" ]]; then
    info "VPS IP: $VPS_IP"
    info "SSH: ssh root@$VPS_IP"
    info "DNS: hermes.${DOMAIN}, status.${DOMAIN}, n8n.${DOMAIN}, auth.${DOMAIN}"

    if run_ssh "systemctl is-active k3s" 2>/dev/null | grep -q active; then
      ok "k3s: active"
      run_ssh "kubectl get pods --all-namespaces" 2>/dev/null || true
    else
      warn "k3s: not active (or SSH failed)"
    fi
  else
    warn "No VPS IP found. Deploy first or export VPS_IP."
  fi
}

phase_destroy() {
  step "Destroy Infrastructure"
  warn "This will DESTROY the VPS and all data!"
  warn "Make sure backups are complete before proceeding."
  prompt_confirm
  echo -n "Type 'destroy' to confirm: "
  read -r confirm
  [[ "$confirm" == "destroy" ]] || { err "Aborted."; exit 1; }

  cd "$DIR/tofu"
  info "Running tofu destroy..."
  tofu destroy

  ok "Infrastructure destroyed."
}

# ── Main ─────────────────────────────────────────────────────
main() {
  cd "$DIR"

  ***REMOVED*** Render vault-driven templates for all deployment paths. status/destroy/help
  ***REMOVED*** do not need the vault, so skip them to avoid unnecessary Bitwarden calls.
  case "${1:-}" in
    status|destroy|help|--help|-h) : ;;
    *) phase_inventory_render ;;
  esac

  case "${1:-}" in
    status)
      phase_status
      ;;
    destroy)
      phase_destroy
      ;;
    --skip-tofu)
      phase_infect
      phase_nixos
      phase_ansible
      phase_helmfile
      phase_kubectl
      ;;
    --skip-infect)
      phase_tofu
      phase_nixos
      phase_ansible
      phase_helmfile
      phase_kubectl
      ;;
    --skip-nixos)
      phase_tofu
      phase_infect
      phase_ansible
      phase_helmfile
      phase_kubectl
      ;;
    --skip-ansible)
      phase_tofu
      phase_infect
      phase_nixos
      phase_helmfile
      phase_kubectl
      ;;
    --skip-helmfile)
      phase_tofu
      phase_infect
      phase_nixos
      phase_ansible
      phase_kubectl
      ;;
    --skip-kubectl)
      phase_tofu
      phase_infect
      phase_nixos
      phase_ansible
      phase_helmfile
      ;;
    help|--help|-h)
      head -20 "$0"
      ;;
    *)
      phase_tofu
      phase_infect
      phase_nixos
      phase_ansible
      phase_helmfile
      phase_kubectl
      step "Deployment complete! 🚀"
      info "Access your agent at https://hermes.${DOMAIN}"
      info "Status dashboard at https://status.${DOMAIN}"
      info "n8n at https://n8n.${DOMAIN} (Tailscale-only)"
      info "Auth at https://auth.${DOMAIN} (Tailscale-only)"
      info "SSH: ssh root@$VPS_IP"
      ;;
  esac
}

main "$@"
