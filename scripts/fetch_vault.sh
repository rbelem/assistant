#!/usr/bin/env bash
# fetch_vault.sh — Pull deployment config from Bitwarden Secrets Manager (SM)
# and render to:
#   1. .rendered/vault.env        — sourceable shell env vars (envsubst input)
#   2. .rendered/terraform.tfvars — tofu apply -var-file=
#   3. .rendered/runtime-config.json — Nix modules via builtins.fromJSON
#
# Uses the `bws` CLI (official Bitwarden Secrets Manager CLI). Authentication is
# via a machine-account access token — no master password, no interactive login.
# Set BWS_ACCESS_TOKEN env or store the token in ~/.config/bitw/config
# (key: sm_access_token).
#
# SM key layout (uppercase snake_case, no prefix — SM project provides namespace):
#   "VPS_SSH_KEY"              — SSH private key (PEM, raw value)
#   "DOMAIN_CONFIG"            — JSON: {"domain":"...","subdomains":[...]}
#   "TOFU_INPUTS"              — JSON: vps_host, vps_ssh_user, vps_ssh_port, TF vars, storage creds
#
# Usage:
#   scripts/fetch_vault.sh              # write all rendered outputs
#   scripts/fetch_vault.sh --check      # verify keys exist; don't write
#   scripts/fetch_vault.sh --out-dir DIR  # custom output directory
#
# The fetched values flow through three sinks (vault.env, terraform.tfvars,
# runtime-config.json). All three are gitignored and rebuilt on every run.
# Bitwarden SM is the only place environment-specific values live.

set -euo pipefail
source "$(dirname "$0")/lib/bws.sh"

#--- arg parsing ----------------------------------------------------------------
CHECK_ONLY=0
OUT_DIR="${OUT_DIR:-.rendered}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)     CHECK_ONLY=1 ;;
    --out-dir)   OUT_DIR="$2"; shift ;;
    -h|--help)   sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)           echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

#--- preflight -----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { echo "missing required binary: $1" >&2; exit 1; }
}
need bws
need jq
need mkdir
need grep
need mktemp
need mv

#--- SM preflight: verify Secrets Manager access token -------------------------
# `bws_check` requires a valid BWS_ACCESS_TOKEN (env var or
# ~/.config/bitw/config key sm_access_token).
bws_check || exit 1

#--- helpers -------------------------------------------------------------------
# Fetch a raw SM secret value by key. Delegates to bws_get from lib/bws.sh.
sm_get() {
  local key="$1"
  bws_get "$key" 2>/dev/null || true
}

assert_non_empty() {
  local label="$1" value="$2"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "Secrets Manager field empty: $label" >&2
    echo "  check SM keys:" >&2
    echo "    1. VPS_SSH_KEY                  2. DOMAIN_CONFIG" >&2
    echo "    3. TOFU_INPUTS                 4. RCLB_DEV_CLOUDFLARE_API_KEY" >&2
    echo "    5. MINIMAX_API_KEY             6. DISCORD_BOT_TOKEN" >&2
    echo "    7. N8N_ENCRYPTION_KEY         8. ZITADEL_MASTERKEY" >&2
    echo "    9. ZITADEL_ADMIN_PASSWORD    10. TAILSCALE_AUTHKEY" >&2
    echo "   11. POSTGRES_PASSWORD         12. OPENCODE_GO_API_KEY" >&2
    echo "   13. HERMES_API_SERVER_KEY     14. DASHBOARD_PASSWORD" >&2
    echo "   15. DASHBOARD_USERNAME        16. DASHBOARD_SECRET" >&2
    echo "   17. OPENROUTER_API_KEY        18. VPS_ROOT_PASSWORD" >&2
    echo "   19. VPS_SUDO_PASSWORD         20. RESTIC_BACKUP_PASSWORD" >&2
    echo "   21. DISCORD_ALLOWED_USERS" >&2
    exit 1
  fi
}

ensure_gitignored() {
  # Fail-closed: refuse to write if .gitignore is missing — prevents accidental
  # commit of a rendered file with real values.
  local rel="$1"
  [[ -f .gitignore ]] || { echo "ERROR: .gitignore missing at repo root — refusing to render" >&2; exit 1; }
  grep -qxF "$rel" .gitignore || echo "$rel" >> .gitignore
}

to_relpath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath --relative-to=. "$p" 2>/dev/null || echo "$p"
  else
    echo "$p"
  fi
}

#--- main fetch ----------------------------------------------------------------
SM_KEY_VPS='VPS_SSH_KEY'
SM_KEY_DOMAIN='DOMAIN_CONFIG'
SM_KEY_TOFU='TOFU_INPUTS'
SM_KEY_CLOUDFLARE='RCLB_DEV_CLOUDFLARE_API_KEY'

# VPS SSH Key (SM raw value → PEM private key)
SSH_PRIVATE_KEY="$(sm_get "$SM_KEY_VPS")"
assert_non_empty "$SM_KEY_VPS" "$SSH_PRIVATE_KEY"
SSH_PUBLIC_KEY="$(ssh-keygen -y -f <(echo "$SSH_PRIVATE_KEY") 2>/dev/null || true)"
assert_non_empty "$SM_KEY_VPS (derived public key)" "$SSH_PUBLIC_KEY"

# Domain Config (SM raw value → JSON body)
DOMAIN_JSON="$(sm_get "$SM_KEY_DOMAIN")"
[[ -n "$DOMAIN_JSON" ]] || { echo "$SM_KEY_DOMAIN value empty" >&2; exit 1; }
echo "$DOMAIN_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "$SM_KEY_DOMAIN value is not valid JSON: $DOMAIN_JSON" >&2; exit 1; }

DOMAIN="$(echo "$DOMAIN_JSON" | jq -r '.domain')"
ZONE="$(echo "$DOMAIN_JSON" | jq -r '.zone')"
SUBDOMAINS_JSON="$(echo "$DOMAIN_JSON" | jq -c '.subdomains')"
SUBDOMAINS_CSV="$(echo "$DOMAIN_JSON" | jq -r '.subdomains | join(",")')"
assert_non_empty "$SM_KEY_DOMAIN.domain"     "$DOMAIN"
assert_non_empty "$SM_KEY_DOMAIN.zone"       "$ZONE"
assert_non_empty "$SM_KEY_DOMAIN.subdomains" "$SUBDOMAINS_JSON"

# Tofu Inputs (SM raw value → JSON body, optional)
TOFU_JSON="$(sm_get "$SM_KEY_TOFU" 2>/dev/null || true)"
[[ -z "$TOFU_JSON" ]] && TOFU_JSON='{}'
echo "$TOFU_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "$SM_KEY_TOFU value is not valid JSON: $TOFU_JSON" >&2; exit 1; }

# VPS host/user/port from tofu-inputs JSON
VPS_HOST="$(echo "$TOFU_JSON" | jq -r '.vps_host // empty')"
VPS_SSH_USER="$(echo "$TOFU_JSON" | jq -r '.vps_ssh_user // empty')"
VPS_SSH_PORT="$(echo "$TOFU_JSON" | jq -r '.vps_ssh_port // empty')"
assert_non_empty "$SM_KEY_TOFU.vps_host"     "$VPS_HOST"
assert_non_empty "$SM_KEY_TOFU.vps_ssh_user" "$VPS_SSH_USER"
assert_non_empty "$SM_KEY_TOFU.vps_ssh_port" "$VPS_SSH_PORT"

# Cloudflare API token (SM raw value)
CLOUDFLARE_API_TOKEN="$(sm_get "$SM_KEY_CLOUDFLARE")"
assert_non_empty "$SM_KEY_CLOUDFLARE" "$CLOUDFLARE_API_TOKEN"

if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "fetch_vault --check: all SM keys present."
  echo "  VPS:    $VPS_SSH_USER@$VPS_HOST:$VPS_SSH_PORT"
  echo "  DOMAIN: $DOMAIN  SUBDOMAINS: $SUBDOMAINS_CSV"
  echo "  CLOUDFLARE: token set (${#CLOUDFLARE_API_TOKEN} chars)"
  exit 0
fi

#--- render --------------------------------------------------------------------
mkdir -p "$OUT_DIR"

ENV_FILE="$OUT_DIR/vault.env"
TFVARS_FILE="$OUT_DIR/terraform.tfvars"
RUNTIME_JSON="$OUT_DIR/runtime-config.json"

# Pre-register outputs in .gitignore (idempotent, fail-closed).
for f in "$ENV_FILE" "$TFVARS_FILE" "$RUNTIME_JSON"; do
  ensure_gitignored "$(to_relpath "$f")"
done

# vault.env: sourceable shell exports. %q handles shell quoting for free.
tmp="$(mktemp)"
{
  printf '# GENERATED by scripts/fetch_vault.sh — DO NOT EDIT OR COMMIT\n'
  printf '# Regenerate at deploy time: scripts/fetch_vault.sh\n\n'
  printf 'export %s=%q\n' VPS_HOST     "$VPS_HOST"
  printf 'export %s=%q\n' VPS_SSH_USER "$VPS_SSH_USER"
  printf 'export %s=%q\n' VPS_SSH_PORT "$VPS_SSH_PORT"
  printf 'export %s=%q\n' DOMAIN       "$DOMAIN"
  printf 'export %s=%q\n' ZONE         "$ZONE"
  printf 'export %s=%q\n' SUBDOMAINS_JSON "$SUBDOMAINS_JSON"
  printf 'export %s=%q\n' SSH_PRIVATE_KEY "$SSH_PRIVATE_KEY"

  # Cloudflare API token — used by the Cloudflare provider (reads CLOUDFLARE_API_TOKEN env var)
  # and passed as Tofu variable (TF_VAR_cloudflare_api_token).
  printf 'export %s=%q\n' CLOUDFLARE_API_TOKEN "$CLOUDFLARE_API_TOKEN"
  printf 'export %s=%q\n' TF_VAR_cloudflare_api_token "$CLOUDFLARE_API_TOKEN"

  # Export arbitrary TF_VAR_* from Tofu Inputs JSON.
  echo "$TOFU_JSON" | jq -r '
    to_entries[]
    | "export TF_VAR_\(.key | ascii_upcase)=\(.value | tostring)"
  '

  # Export selected non-TF vars from Tofu Inputs for envsubst / deploy scripts.
  # These are also written to terraform.tfvars below as Tofu variables.
  # Includes TOFU_STATE_* keys consumed by tofu/tofu-wrapper.sh for the S3 backend.
  echo "$TOFU_JSON" | jq -r '
    to_entries[]
    | select(.key == "project_name" or .key == "vps_plan_code" or .key == "datacenter"
             or .key == "storage_access_key" or .key == "storage_secret_key"
             or .key == "storage_endpoint" or .key == "storage_region"
             or .key == "vps_image_id" or .key == "vps_os"
             or .key == "vps_display_name" or .key == "ssh_public_key"
             or .key == "tofu_state_bucket" or .key == "tofu_state_region"
             or .key == "tofu_state_endpoint" or .key == "tofu_state_access_key"
             or .key == "tofu_state_secret_key")
    | "export \(.key | ascii_upcase)=\(.value | tostring)"
  '

  # Aliases: SM stores Hetzner Object Storage creds as storage_*, but
  # the state bucket lives on the same Hetzner account — tofu/tofu-wrapper.sh
  # reads TOFU_STATE_ACCESS_KEY / TOFU_STATE_SECRET_KEY from env to write
  # .rendered/backend.conf. Without these aliases the wrapper fails with
  # "unbound variable" (set -u). Precedence: explicit tofu_state_* wins
  # when present; storage_* is the fallback (forward-compatible with
  # adding tofu_state_* fields to the SM secret later).
  STATE_ACCESS_KEY="$(echo "$TOFU_JSON" | jq -r '.tofu_state_access_key // .storage_access_key // empty')"
  STATE_SECRET_KEY="$(echo "$TOFU_JSON" | jq -r '.tofu_state_secret_key // .storage_secret_key // empty')"
  printf 'export %s=%q\n' TOFU_STATE_ACCESS_KEY "$STATE_ACCESS_KEY"
  printf 'export %s=%q\n' TOFU_STATE_SECRET_KEY "$STATE_SECRET_KEY"
} > "$tmp"
mv "$tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# terraform.tfvars: passed to tofu via -var-file=.rendered/terraform.tfvars.
tmp="$(mktemp)"
{
  printf '# GENERATED by scripts/fetch_vault.sh — DO NOT EDIT OR COMMIT\n'
  printf '# Regenerate at deploy time. Pass to tofu via:\n'
  printf '#   tofu apply -var-file=.rendered/terraform.tfvars\n\n'
  printf 'domain_name = %s\n' "$(jq -Rn --arg v "$DOMAIN" '$v')"
  printf 'zone_name   = %s\n' "$(jq -Rn --arg v "$ZONE" '$v')"
  printf 'ssh_user    = %s\n' "$(jq -Rn --arg v "$VPS_SSH_USER" '$v')"
  printf 'ssh_port    = %d\n' "$VPS_SSH_PORT"
  printf 'subdomains  = %s\n' "$SUBDOMAINS_JSON"

  # Append any extra Tofu Inputs as tfvars — keys map verbatim (caller has
  # already declared matching variables in tofu/variables.tf).
  # Exclude TOFU_STATE_* keys; those are consumed by tofu-wrapper.sh from env vars,
  # not passed as Tofu input variables.
  echo "$TOFU_JSON" | jq -r '
    to_entries[]
    | select(.key != "domain_name" and .key != "ssh_user" and .key != "vps_ip"
             and .key != "ssh_port" and .key != "subdomains"
             and .key != "tofu_state_bucket" and .key != "tofu_state_region"
             and .key != "tofu_state_endpoint" and .key != "tofu_state_access_key"
             and .key != "tofu_state_secret_key"
             and .key != "state_bucket_name" and .key != "storage_region"
              and .key != "storage_endpoint"
              and .key != "vps_ssh_user" and .key != "vps_ssh_port" and .key != "vps_host"
              and .key != "initial_ssh_user" and .key != "hcloud_ssh_key_fingerprint"
              and .key != "hcloud_image_filter")
    | "\(.key) = \(.value | tojson)"
  '
  # Aliases: SM uses tofu_state_* prefix; tofu/variables.tf uses storage_* / state_bucket_name.
  # Emit both so the variable names tofu expects are satisfied.
  STATE_BUCKET="$(echo "$TOFU_JSON" | jq -r '.tofu_state_bucket // .state_bucket_name // empty')"
  STATE_REGION="$(echo "$TOFU_JSON" | jq -r '.tofu_state_region // .storage_region // empty')"
  STATE_ENDPOINT="$(echo "$TOFU_JSON" | jq -r '.tofu_state_endpoint // .storage_endpoint // empty')"
  printf 'state_bucket_name = %s\n' "$(jq -n --arg v "$STATE_BUCKET" '$v')"
  printf 'storage_region    = %s\n' "$(jq -n --arg v "$STATE_REGION" '$v')"
  printf 'storage_endpoint  = %s\n' "$(jq -n --arg v "$STATE_ENDPOINT" '$v')"
  printf 'ssh_public_key    = %s\n' "$(jq -n --arg v "$SSH_PUBLIC_KEY" '$v')"
  VPS_DISPLAY_NAME="$(echo "$TOFU_JSON" | jq -r '.vps_display_name // "zet"')"
  printf 'vps_display_name  = %s\n' "$(jq -n --arg v "$VPS_DISPLAY_NAME" '$v')"
  printf 'cloudflare_api_token = %s\n' "$(jq -n --arg v "$CLOUDFLARE_API_TOKEN" '$v')"
} > "$tmp"
mv "$tmp" "$TFVARS_FILE"
chmod 600 "$TFVARS_FILE"

# runtime-config.json: read by Nix modules via builtins.fromJSON
# (Option A per prior Oracle review — gitignored file visible via `path:` flakeref).
# Backup S3 config removed 2026-07-27 (restic backups deferred).

jq -n \
  --arg domain "$DOMAIN" \
  --arg zone "$ZONE" \
  --arg vps_host "$VPS_HOST" \
  --arg ssh_user "$VPS_SSH_USER" \
  --argjson ssh_port "$VPS_SSH_PORT" \
  --argjson subdomains "$SUBDOMAINS_JSON" \
  --argjson tofu "$TOFU_JSON" \
  --arg ssh_private_key "$SSH_PRIVATE_KEY" \
  '{
     domain:     $domain,
     zone:       $zone,
     subdomains: $subdomains,
     vps_host:   $vps_host,
     ssh_user:   $ssh_user,
     ssh_port:   $ssh_port,
     ssh_private_key: $ssh_private_key,
     tofu:       $tofu
   }' \
  > "$RUNTIME_JSON"
chmod 600 "$RUNTIME_JSON"

#--- summary -------------------------------------------------------------------
echo
echo "fetch_vault: rendered (from Secrets Manager)."
echo "  VPS:    $VPS_SSH_USER@$VPS_HOST:$VPS_SSH_PORT"
echo "  DOMAIN: $DOMAIN"
echo "  SUBS:   $SUBDOMAINS_CSV"
echo "  CLOUDFLARE: token set (${#CLOUDFLARE_API_TOKEN} chars)"
echo "  env:    $ENV_FILE"
echo "  tfvars: $TFVARS_FILE"
echo "  nix:    $RUNTIME_JSON"
echo
echo "Next steps:"
echo "  source $ENV_FILE                       # loads VPS_HOST, DOMAIN, etc."
echo "  tofu apply -var-file=$TFVARS_FILE      # Tofu with SM-driven inputs"
echo "  nixos-rebuild build --flake path:\$NIX_CONFIG_DIR#zet  # Nix reads runtime-config.json"
