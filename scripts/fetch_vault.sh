#!/usr/bin/env bash
# fetch_vault.sh — Pull deployment config from Bitwarden and render to:
#   1. .rendered/vault.env        — sourceable shell env vars (envsubst input)
#   2. .rendered/terraform.tfvars — tofu apply -var-file=
#   3. .rendered/runtime-config.json — Nix modules via builtins.fromJSON
#
# Uses the `bitw` CLI (rbelem fork). bitw auto-unlocks via libsecret keyring
# (entry "bitwarden master-password"), or the PASSWORD env var, or an
# interactive prompt. No session tokens, no BW_SESSION.
#
# Bitwarden schema (vault `assistant`, items namespaced under that prefix):
#   "assistant/vps-ssh-key"    — SSH key (type 5), .sshKey.privateKey
#   "assistant/domain-config"  — Secure Note JSON:
#                                     {"domain":"<your-domain>","subdomains":["hermes",...]}
#   "assistant/tofu-inputs"    — Secure Note JSON (arbitrary TF_VAR_* keys + vps_host, vps_ssh_user, vps_ssh_port)
#
# Usage:
#   scripts/fetch_vault.sh              # write all rendered outputs
#   scripts/fetch_vault.sh --check      # verify items exist; don't write
#   scripts/fetch_vault.sh --out-dir DIR  # custom output directory
#
# Auto-unlock: if secret-tool (libsecret) is available and a Bitwarden master
# password is stored in the keyring under "bitwarden master-password", bitw
# unlocks transparently. Otherwise set PASSWORD env or run `bitw login` first.
#
# The fetched values flow through three sinks (vault.env, terraform.tfvars,
# runtime-config.json). All three are gitignored and rebuilt on every run.
# Bitwarden is the only place environment-specific values live.

set -euo pipefail

#--- arg parsing ----------------------------------------------------------------
CHECK_ONLY=0
OUT_DIR="${OUT_DIR:-.rendered}"
BW_ORG_ID="${BW_ORG_ID:-}"   # empty = personal vault; set for org vault (kept for compat)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)     CHECK_ONLY=1 ;;
    --out-dir)   OUT_DIR="$2"; shift ;;
    --org-id)    BW_ORG_ID="$2"; shift ;;
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
need bitw
need jq
need mkdir
need grep
need mktemp
need mv

#--- bitw preflight: verify login tokens exist --------------------------------
# bitw status exits 0 when tokens exist (does NOT require unlock).
# If tokens are missing, the operator needs to run `bitw login` once.
if ! bitw status 2>/dev/null | grep -q 'token_valid.*valid'; then
  cat >&2 <<EOF
bitw login tokens not found. Two ways to fix:
  1. Run \`bitw login\` (interactive) to store login tokens.
  2. Store master password in system keyring for auto-unlock:
       secret-tool store --label="Bitwarden" bitwarden master-password
     (bitw will use it automatically from then on)
EOF
  exit 1
fi

# Sync the local vault cache with the server. bitw reads from a local encrypted
# DB; unlock decrypts it but doesn't refresh it. Without this, items created
# via web/extension/another machine are invisible to `bitw get` and
# every fetch returns empty. Idempotent + fast (~200ms when current).
bitw sync 2>/dev/null || true

#--- helpers -------------------------------------------------------------------
# Pull the JSON payload of a Secure Note item by name.
# bitw get --json finds items by name regardless of org.
fetch_note_payload() {
  local item_name="$1"
  bitw get --json "$item_name" 2>/dev/null | jq -r '.notes // ""'
}

assert_non_empty() {
  local label="$1" value="$2"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "Bitwarden field empty: $label" >&2
<<<<<<< HEAD
    echo "  check items:" >&2
    echo "    1. assistant/minimax-api-key          2. assistant/hermes-discord-token" >&2
    echo "    3. assistant/n8n-encryption-key       4. assistant/zitadel-masterkey" >&2
    echo "    5. assistant/zitadel-admin-password   6. assistant/porkbun-api-key" >&2
    echo "    7. assistant/porkbun-secret-api-key   8. assistant/tailscale-authkey" >&2
    echo "    9. assistant/caddy-admin-password     10. assistant/postgres-password" >&2
    echo "    11. assistant/vps-ssh-key             12. assistant/domain-config" >&2
    echo "    13. assistant/tofu-inputs" >&2
||||||| parent of a48dc0a (refactor(secrets): batch BW item rename to assistant/<kebab> convention)
    echo "  check items 'assistant/vps-ssh-key', 'assistant/domain-config', 'assistant/tofu-inputs', 'assistant/porkbun-api-key'" >&2
=======
    echo "  check items:" >&2
    echo "    1. assistant/openrouter-api-key    2. assistant/hermes-discord-token" >&2
    echo "    3. assistant/n8n-encryption-key    4. assistant/zitadel-masterkey" >&2
    echo "    5. assistant/zitadel-admin-password 6. assistant/porkbun-api-key" >&2
    echo "    7. assistant/lambda-cloud-api-key  8. assistant/tailscale-authkey" >&2
    echo "    9. assistant/caddy-admin-password  10. assistant/restic-backup-password" >&2
    echo "    11. assistant/ovh-object-storage   12. assistant/postgres-password" >&2
    echo "    13. assistant/vps-ssh-key          14. assistant/domain-config" >&2
    echo "    15. assistant/tofu-inputs" >&2
>>>>>>> a48dc0a (refactor(secrets): batch BW item rename to assistant/<kebab> convention)
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
ITEM_VPS='assistant/vps-ssh-key'
ITEM_DOMAIN='assistant/domain-config'
ITEM_TOFU='assistant/tofu-inputs'
ITEM_PORKBUN='assistant/porkbun-api-key'
ITEM_PORKBUN_SECRET='assistant/porkbun-secret-api-key'

# VPS SSH Key (SSH key type → .sshKey.{privateKey,publicKey})
SSH_KEY_ITEM="$(bitw get --json "$ITEM_VPS")"
SSH_PRIVATE_KEY="$(echo "$SSH_KEY_ITEM" | jq -r '.sshKey.privateKey // ""')"
SSH_PUBLIC_KEY="$(echo "$SSH_KEY_ITEM" | jq -r '.sshKey.publicKey // ""')"
assert_non_empty "$ITEM_VPS.sshKey.privateKey" "$SSH_PRIVATE_KEY"
[[ -z "$SSH_PUBLIC_KEY" ]] && SSH_PUBLIC_KEY="$(ssh-keygen -y -f <(echo "$SSH_PRIVATE_KEY") 2>/dev/null || true)"
assert_non_empty "$ITEM_VPS.sshKey.publicKey" "$SSH_PUBLIC_KEY"

# Domain Config (Secure Note → JSON body)
DOMAIN_JSON="$(fetch_note_payload "$ITEM_DOMAIN")"
[[ -n "$DOMAIN_JSON" ]] || { echo "$ITEM_DOMAIN note body empty" >&2; exit 1; }
echo "$DOMAIN_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "$ITEM_DOMAIN body is not valid JSON: $DOMAIN_JSON" >&2; exit 1; }

DOMAIN="$(echo "$DOMAIN_JSON" | jq -r '.domain')"
SUBDOMAINS_JSON="$(echo "$DOMAIN_JSON" | jq -c '.subdomains')"
SUBDOMAINS_CSV="$(echo "$DOMAIN_JSON" | jq -r '.subdomains | join(",")')"
assert_non_empty "$ITEM_DOMAIN.domain"     "$DOMAIN"
assert_non_empty "$ITEM_DOMAIN.subdomains" "$SUBDOMAINS_JSON"

# Tofu Inputs (Secure Note → JSON body, optional)
TOFU_JSON="$(fetch_note_payload "$ITEM_TOFU" 2>/dev/null || true)"
[[ -z "$TOFU_JSON" ]] && TOFU_JSON='{}'
echo "$TOFU_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "$ITEM_TOFU body is not valid JSON: $TOFU_JSON" >&2; exit 1; }

# VPS host/user/port from tofu-inputs JSON (moved from vps-access Login item)
VPS_HOST="$(echo "$TOFU_JSON" | jq -r '.vps_host // empty')"
VPS_SSH_USER="$(echo "$TOFU_JSON" | jq -r '.vps_ssh_user // empty')"
VPS_SSH_PORT="$(echo "$TOFU_JSON" | jq -r '.vps_ssh_port // empty')"
assert_non_empty "$ITEM_TOFU.vps_host"     "$VPS_HOST"
assert_non_empty "$ITEM_TOFU.vps_ssh_user" "$VPS_SSH_USER"
assert_non_empty "$ITEM_TOFU.vps_ssh_port" "$VPS_SSH_PORT"

# assistant/porkbun-api-key + assistant/porkbun-secret-api-key (each Login, password field)
PORKBUN_API_KEY="$(bitw get --field password "$ITEM_PORKBUN")"
PORKBUN_SECRET_API_KEY="$(bitw get --field password "$ITEM_PORKBUN_SECRET")"
assert_non_empty "$ITEM_PORKBUN (password)"        "$PORKBUN_API_KEY"
assert_non_empty "$ITEM_PORKBUN_SECRET (password)" "$PORKBUN_SECRET_API_KEY"

if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "fetch_vault --check: all items present."
  echo "  VPS:    $VPS_SSH_USER@$VPS_HOST:$VPS_SSH_PORT"
  echo "  DOMAIN: $DOMAIN  SUBDOMAINS: $SUBDOMAINS_CSV"
  echo "  PORKBUN: api_key=${PORKBUN_API_KEY:0:4}… secret=${PORKBUN_SECRET_API_KEY:0:4}…"
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
  printf 'export %s=%q\n' SUBDOMAINS_JSON "$SUBDOMAINS_JSON"
  printf 'export %s=%q\n' SSH_PRIVATE_KEY "$SSH_PRIVATE_KEY"
  printf 'export %s=%q\n' PORKBUN_API_KEY "$PORKBUN_API_KEY"
  printf 'export %s=%q\n' PORKBUN_SECRET_API_KEY "$PORKBUN_SECRET_API_KEY"
  printf 'export %s=%q\n' TF_VAR_porkbun_api_key "$PORKBUN_API_KEY"
  printf 'export %s=%q\n' TF_VAR_porkbun_secret_api_key "$PORKBUN_SECRET_API_KEY"

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

  # Aliases: the BW note stores Hetzner Object Storage creds as storage_*, but
  # the state bucket lives on the same Hetzner account — tofu/tofu-wrapper.sh
  # reads TOFU_STATE_ACCESS_KEY / TOFU_STATE_SECRET_KEY from env to write
  # .rendered/backend.conf. Without these aliases the wrapper fails with
  # "unbound variable" (set -u). Precedence: explicit tofu_state_* wins
  # when present; storage_* is the fallback (forward-compatible with
  # adding tofu_state_* fields to the BW note later).
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
  printf 'ssh_user    = %s\n' "$(jq -Rn --arg v "$VPS_SSH_USER" '$v')"
  printf 'vps_ip      = %s\n' "$(jq -Rn --arg v "$VPS_HOST" '$v')"
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
  # Aliases: bitw uses tofu_state_* prefix; tofu/variables.tf uses storage_* / state_bucket_name.
  # Emit both so the variable names tofu expects are satisfied.
  STATE_BUCKET="$(echo "$TOFU_JSON" | jq -r '.tofu_state_bucket // .state_bucket_name // empty')"
  STATE_REGION="$(echo "$TOFU_JSON" | jq -r '.tofu_state_region // .storage_region // empty')"
  STATE_ENDPOINT="$(echo "$TOFU_JSON" | jq -r '.tofu_state_endpoint // .storage_endpoint // empty')"
  printf 'state_bucket_name = %s\n' "$(jq -n --arg v "$STATE_BUCKET" '$v')"
  printf 'storage_region    = %s\n' "$(jq -n --arg v "$STATE_REGION" '$v')"
  printf 'storage_endpoint  = %s\n' "$(jq -n --arg v "$STATE_ENDPOINT" '$v')"
  printf 'ssh_public_key    = %s\n' "$(jq -n --arg v "$SSH_PUBLIC_KEY" '$v')"
  printf 'porkbun_api_key        = %s\n' "$(jq -Rn --arg v "$PORKBUN_API_KEY" '$v')"
  printf 'porkbun_secret_api_key = %s\n' "$(jq -Rn --arg v "$PORKBUN_SECRET_API_KEY" '$v')"
  VPS_DISPLAY_NAME="$(echo "$TOFU_JSON" | jq -r '.vps_display_name // "agent"')"
  printf 'vps_display_name  = %s\n' "$(jq -n --arg v "$VPS_DISPLAY_NAME" '$v')"
} > "$tmp"
mv "$tmp" "$TFVARS_FILE"
chmod 600 "$TFVARS_FILE"

<<<<<<< HEAD
# runtime-config.json: read by Nix modules via builtins.fromJSON
# (Option A per prior Oracle review — gitignored file visible via `path:` flakeref).
# Backup S3 config removed 2026-07-27 (restic backups deferred).

||||||| parent of 28e82a5 (fix(deploy): address oracle review blockers)
***REMOVED*** runtime-config.json: read by Nix modules via builtins.fromJSON
***REMOVED*** (Option A per prior Oracle review — gitignored file visible via `path:` flakeref).
=======
***REMOVED*** runtime-config.json: read by Nix modules via builtins.fromJSON
***REMOVED*** (Option A per prior Oracle review — gitignored file visible via `path:` flakeref).
***REMOVED*** Extract backup S3 config from tofu-inputs (consumed by nix-config backup.nix)
BACKUP_S3_ENDPOINT="$(echo "$TOFU_JSON" | jq -r '.storage_endpoint // empty')"
BACKUP_S3_BUCKET="$(echo "$TOFU_JSON" | jq -r '.backup_bucket_name // empty')"

>>>>>>> 28e82a5 (fix(deploy): address oracle review blockers)
jq -n \
  --arg domain "$DOMAIN" \
  --arg vps_host "$VPS_HOST" \
  --arg ssh_user "$VPS_SSH_USER" \
  --argjson ssh_port "$VPS_SSH_PORT" \
  --argjson subdomains "$SUBDOMAINS_JSON" \
  --argjson tofu "$TOFU_JSON" \
  --arg ssh_private_key "$SSH_PRIVATE_KEY" \
  --arg backup_s3_endpoint "$BACKUP_S3_ENDPOINT" \
  --arg backup_s3_bucket "$BACKUP_S3_BUCKET" \
  '{
     domain:     $domain,
     subdomains: $subdomains,
     vps_host:   $vps_host,
     ssh_user:   $ssh_user,
     ssh_port:   $ssh_port,
     ssh_private_key: $ssh_private_key,
     tofu:       $tofu,
     backup: {
       s3: {
         endpoint: $backup_s3_endpoint,
         bucket:   $backup_s3_bucket
       }
     }
   }' \
  > "$RUNTIME_JSON"
chmod 600 "$RUNTIME_JSON"

#--- summary -------------------------------------------------------------------
echo
echo "fetch_vault: rendered."
echo "  VPS:    $VPS_SSH_USER@$VPS_HOST:$VPS_SSH_PORT"
echo "  DOMAIN: $DOMAIN"
echo "  SUBS:   $SUBDOMAINS_CSV"
echo "  PORKBUN: api_key set (${#PORKBUN_API_KEY} chars)"
echo "  env:    $ENV_FILE"
echo "  tfvars: $TFVARS_FILE"
echo "  nix:    $RUNTIME_JSON"
echo
echo "Next steps:"
echo "  source $ENV_FILE                       # loads VPS_HOST, DOMAIN, etc."
echo "  tofu apply -var-file=$TFVARS_FILE      # Tofu with vault-driven inputs"
echo "  nixos-rebuild build --flake path:\$NIX_CONFIG_DIR#agent  # Nix reads runtime-config.json"
