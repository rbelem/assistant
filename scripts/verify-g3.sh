***REMOVED***!/usr/bin/env bash
***REMOVED*** verify-g3.sh — verify VPS has no Bitwarden master password artifacts.
***REMOVED***
***REMOVED*** Asserts that the VPS is clean of:
***REMOVED***   - /etc/agent/bw_master_pw (systemd EnvironmentFile for bitw PASSWORD)
***REMOVED***   - /root/.bw_session.sh (session helper script)
***REMOVED***   - ~/.config/bitw (SM token config)
***REMOVED***   - ~/.local/share/bitw (data)
***REMOVED***   - bitw binary (VPS should not have bitw installed)
***REMOVED***   - bws binary (VPS should not have the SM CLI installed)
***REMOVED***   - BWS_ACCESS_TOKEN env var (SM access token never touches the VPS)
***REMOVED***
***REMOVED*** This is a security gate: the master password never touches the VPS.
***REMOVED*** Secrets are rendered on the workstation and applied via ansible.
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   scripts/verify-g3.sh              ***REMOVED*** verify VPS is clean
***REMOVED***   scripts/verify-g3.sh --help       ***REMOVED*** this message
***REMOVED***
***REMOVED*** Environment:
***REMOVED***   VPS_IP      VPS IP address (default: from tofu output or inventory)
***REMOVED***   SSH_KEY     SSH private key (default: from .rendered/vault.env or ~/.ssh/id_ed25519)
***REMOVED***   SSH_USER    SSH user (default: from inventory or rodrigo)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

***REMOVED*** Colors
if [[ -t 2 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info()  { echo -e "${BLUE}:: $*${NC}" >&2; }
ok()    { echo -e "${GREEN}✓  $*${NC}" >&2; }
err()   { echo -e "${RED}✗ $*${NC}" >&2; }

***REMOVED*** Arg parsing
while [[ $***REMOVED*** -gt 0 ]]; do
  case "$1" in
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^***REMOVED*** \?//'; exit 0 ;;
    *)          err "unknown arg: $1"; exit 1 ;;
  esac
  shift
done

***REMOVED*** Source vault.env if available (for SSH_PRIVATE_KEY)
***REMOVED*** shellcheck disable=SC1091
[[ -f "$REPO_ROOT/.rendered/vault.env" ]] && . "$REPO_ROOT/.rendered/vault.env"

***REMOVED*** Resolve VPS IP
if [[ -z "${VPS_IP:-}" ]]; then
  if [[ -f "$REPO_ROOT/tofu/terraform.tfstate" ]] || [[ -d "$REPO_ROOT/tofu/.terraform" ]]; then
    VPS_IP="$(tofu -chdir="$REPO_ROOT/tofu" output -raw vps_ip 2>/dev/null || true)"
  fi
fi

if [[ -z "${VPS_IP:-}" ]]; then
  ***REMOVED*** Try inventory
  if [[ -f "$REPO_ROOT/ansible/inventory/hosts.yml" ]]; then
    VPS_IP="$(grep 'ansible_host:' "$REPO_ROOT/ansible/inventory/hosts.yml" | awk '{print $2}' || true)"
  fi
fi

if [[ -z "${VPS_IP:-}" || "$VPS_IP" == "TBD.pending.tofu.apply" ]]; then
  err "VPS_IP not set and could not be determined."
  err "Set VPS_IP env var or run after tofu apply."
  exit 1
fi

***REMOVED*** Resolve SSH key
SSH_KEY_FILE="${SSH_KEY:-}"
if [[ -z "$SSH_KEY_FILE" && -n "${SSH_PRIVATE_KEY:-}" ]]; then
  SSH_KEY_FILE="$(mktemp -t verify_g3_key.XXXXXX)"
  chmod 600 "$SSH_KEY_FILE"
  printf '%s\n' "$SSH_PRIVATE_KEY" > "$SSH_KEY_FILE"
  trap 'rm -f "$SSH_KEY_FILE"' EXIT
elif [[ -z "$SSH_KEY_FILE" && -f "${HOME}/.ssh/id_ed25519" ]]; then
  SSH_KEY_FILE="${HOME}/.ssh/id_ed25519"
fi

SSH_KEY_ARG=""
if [[ -n "$SSH_KEY_FILE" ]]; then
  SSH_KEY_ARG="-i $SSH_KEY_FILE"
fi

***REMOVED*** Resolve SSH user
SSH_USER="${SSH_USER:-${VPS_SSH_USER:-rodrigo}}"

info "Verifying VPS at $SSH_USER@$VPS_IP is clean of master password artifacts..."
echo

***REMOVED*** Run verification checks on VPS
***REMOVED*** Each check prints its status; we collect failures and report at the end.
FAILURES=0

check_vps() {
  local description="$1"
  local cmd="$2"

  if ssh $SSH_KEY_ARG -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       "$SSH_USER@$VPS_IP" "$cmd" 2>/dev/null; then
    ok "$description"
  else
    err "$description"
    FAILURES=$((FAILURES + 1))
  fi
}

check_vps "/etc/agent/bw_master_pw does not exist" \
  "test ! -f /etc/agent/bw_master_pw"

check_vps "/root/.bw_session.sh does not exist" \
  "test ! -f /root/.bw_session.sh"

check_vps "/root/.config/bitw does not exist" \
  "test ! -d ~/.config/bitw"

check_vps "/root/.local/share/bitw does not exist" \
  "test ! -d ~/.local/share/bitw"

check_vps "bws binary not installed" \
  "! command -v bws >/dev/null 2>&1"

check_vps "bitw binary not installed" \
  "! command -v bitw >/dev/null 2>&1"

check_vps "BWS_ACCESS_TOKEN not in environment" \
  "test -z \"\$BWS_ACCESS_TOKEN\""

echo
if [[ "$FAILURES" -eq 0 ]]; then
  ok "VPS-CLEAN: no master password artifacts found."
  exit 0
else
  err "VPS-DIRTY: $FAILURES check(s) failed."
  err "The VPS should not have master password files."
  err "If this is a fresh VPS, run the deploy pipeline."
  err "If this is an existing VPS, manually remove the artifacts:"
  err "  ssh $SSH_USER@$VPS_IP"
  err "  sudo rm -f /etc/agent/bw_master_pw /root/.bw_session.sh; sudo rm -rf ~/.config/bitw ~/.local/share/bitw"
  exit 1
fi
