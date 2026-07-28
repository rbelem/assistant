***REMOVED***!/usr/bin/env bash
***REMOVED***populate-vault.sh — Create the 3 Bitwarden items needed for the
***REMOVED***Bitwarden+template externalization architecture. Idempotent: skips items
***REMOVED***that already exist.
***REMOVED***
***REMOVED***Pattern from devbox secrets-add: bw_sesh wrapper, keyring auto-unlock.
***REMOVED***
***REMOVED***Required env vars:
***REMOVED***VPS_HOST          — current VPS public IPv4
***REMOVED***DOMAIN            — base domain (e.g. example.com)
***REMOVED***SUBDOMAINS_JSON   — JSON array (e.g. '["app","www"]')
***REMOVED***PROJECT_NAME      — project prefix (e.g. assistant)
***REMOVED***TOFU_INPUTS_JSON  — JSON object with Tofu vars (plan, datacenter, etc.)
***REMOVED***SSH_PRIVATE_KEY   — SSH private key (PEM format)
***REMOVED***SSH_PUBLIC_KEY    — SSH public key (e.g. ssh-ed25519 AAAA...)
***REMOVED***
***REMOVED***Optional env vars (with defaults):
***REMOVED***SSH_USER          — SSH user (default: root)
***REMOVED***SSH_PORT          — SSH port (default: 22)
***REMOVED***
***REMOVED***Usage:
***REMOVED***VPS_HOST=203.0.113.42 DOMAIN=example.com \
***REMOVED***PROJECT_NAME=assistant \
***REMOVED***SUBDOMAINS_JSON='["app","www"]' \
***REMOVED***TOFU_INPUTS_JSON='{"vps_plan_code":"KVM 4","datacenter":"gra","vps_image_id":"...","state_bucket_name":"...-tofu-state","storage_region":"gra","storage_endpoint":"https://s3.gra.io.REDACTED-OVH-DOMAIN","storage_access_key":"...","storage_secret_key":"...","ssh_public_key":"...","vps_os":"debian-12","vps_display_name":"agent"}' \
***REMOVED***scripts/populate-vault.sh
***REMOVED***
***REMOVED***After successful run: scripts/fetch_vault.sh --check  ***REMOVED*** validate schema

set -euo pipefail

***REMOVED***--- arg validation ------------------------------------------------------------
: "${VPS_HOST:?must set VPS_HOST (VPS public IPv4)}"
: "${DOMAIN:?must set DOMAIN (e.g. example.com)}"
: "${SUBDOMAINS_JSON:?must set SUBDOMAINS_JSON (JSON array string)}"
: "${PROJECT_NAME:?must set PROJECT_NAME (e.g. assistant)}"
: "${TOFU_INPUTS_JSON:?must set TOFU_INPUTS_JSON (JSON object)}"
: "${SSH_PRIVATE_KEY:?must set SSH_PRIVATE_KEY (PEM format)}"
: "${SSH_PUBLIC_KEY:?must set SSH_PUBLIC_KEY (e.g. ssh-ed25519 AAAA...)}"

SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"

***REMOVED***--- preflight ----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { echo "missing required binary: $1" >&2; exit 1; }
}
need bw
need jq

***REMOVED***Validate JSON payloads up front
echo "$SUBDOMAINS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "SUBDOMAINS_JSON is not valid JSON: $SUBDOMAINS_JSON" >&2; exit 1; }
echo "$TOFU_INPUTS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "TOFU_INPUTS_JSON is not valid JSON: $TOFU_INPUTS_JSON" >&2; exit 1; }

***REMOVED***--- BW_SESSION resolution: keyring first, then env fallback -------------------
if [[ -z "${BW_SESSION:-}" ]] && command -v secret-tool >/dev/null 2>&1; then
  if master_pw="$(secret-tool lookup bitwarden master-password 2>/dev/null)" \
     && [[ -n "$master_pw" ]]; then
    if BW_SESSION="$(bw unlock --raw "$master_pw" 2>/dev/null)" \
       && [[ -n "$BW_SESSION" ]]; then
      export BW_SESSION
    fi
    unset master_pw
  fi
fi

[[ -n "${BW_SESSION:-}" ]] \
  || {
    cat >&2 <<EOF
BW_SESSION not resolved. Two options:
  1. Recommended: store master password in keyring once.
       secret-tool store --label="Bitwarden" bitwarden master-password
     (this script will auto-unlock from then on)
  2. One-off:
       bw unlock --raw > ~/.bw_session_token
       export BW_SESSION=\$(cat ~/.bw_session_token)
EOF
    exit 1
  }

bw_sesh() { bw --session "$BW_SESSION" "$@"; }

***REMOVED***--- helpers -------------------------------------------------------------------
create_if_missing() {
  local name="$1" item_json="$2"
  if bw_sesh get item "$name" >/dev/null 2>&1; then
    echo "  ⊘ $name (already exists — skip; delete first if you want to recreate)"
    return 0
  fi
  local encoded err
  encoded="$(echo "$item_json" | bw_sesh encode 2>/dev/null)" || {
    echo "  ✗ $name: bw encode failed" >&2; return 1
  }
  err="$(printf '%s' "$encoded" | bw_sesh create item 2>&1)" || {
    echo "  ✗ $name: bw create item failed: $err" >&2; return 1
  }
  echo "  ✓ $name (created)"
}

***REMOVED***--- item 1: assistant/vps-ssh-key (SSH key type) -----------------------------
echo
echo "Creating assistant/vps-ssh-key (SSH key type)..."
ssh_key_item="$(jq -n \
  --arg name "assistant/vps-ssh-key" \
  --arg private_key "$SSH_PRIVATE_KEY" \
  --arg public_key "$SSH_PUBLIC_KEY" \
  '{
     type: 5,
     name: $name,
     sshKey: {
       privateKey: $private_key,
       publicKey: $public_key
     }
   }')"
create_if_missing "assistant/vps-ssh-key" "$ssh_key_item"

***REMOVED***--- item 2: assistant/domain-config (Secure Note + JSON) ------------------
echo
echo "Creating assistant/domain-config (Secure Note)..."
domain_item="$(jq -n \
  --arg name "assistant/domain-config" \
  --arg domain "$DOMAIN" \
  --argjson subdomains "$SUBDOMAINS_JSON" \
  '{
     type: 2,
     name: $name,
     notes: ({ domain: $domain, subdomains: $subdomains } | tojson)
   }')"
create_if_missing "assistant/domain-config" "$domain_item"

***REMOVED***--- item 3: assistant/tofu-inputs (Secure Note + JSON) --------------------
echo
echo "Creating assistant/tofu-inputs (Secure Note)..."
tofu_item="$(jq -n \
  --arg name "assistant/tofu-inputs" \
  --argjson inputs "$TOFU_INPUTS_JSON" \
  --arg project "$PROJECT_NAME" \
  --arg domain "$DOMAIN" \
  --arg host "$VPS_HOST" \
  --arg user "$SSH_USER" \
  --argjson port "$SSH_PORT" \
  '{
     type: 2,
     name: $name,
     notes: (
       { project_name: $project, domain: $domain, vps_host: $host, vps_ssh_user: $user, vps_ssh_port: $port } + $inputs
       | tojson
     )
   }')"
create_if_missing "assistant/tofu-inputs" "$tofu_item"

***REMOVED***--- verify -------------------------------------------------------------------
echo
echo "Verifying items are retrievable..."
all_ok=1
for name in assistant/vps-ssh-key assistant/domain-config assistant/tofu-inputs; do
  if bw_sesh get item "$name" >/dev/null 2>&1; then
    echo "  ✓ $name retrievable"
  else
    echo "  ✗ $name NOT retrievable" >&2
    all_ok=0
  fi
done

[[ "$all_ok" == "1" ]] || { echo "Verification failed." >&2; exit 1; }

***REMOVED***--- summary ------------------------------------------------------------------
echo
echo "All 3 items created/verified."
echo
echo "Next step: validate the schema + render end-to-end:"
echo "  scripts/fetch_vault.sh --check"
echo
echo "To update values later, edit the items in Bitwarden or via bw CLI:"
echo "  bw get item 'assistant/tofu-inputs' | jq -r '.notes | fromjson'"
echo
echo "Required TOFU_INPUTS_JSON keys (for full deploy):"
echo '  vps_plan_code, datacenter, vps_image_id, vps_os, vps_display_name,'
echo '  ssh_public_key, state_bucket_name, storage_region,'
echo '  storage_endpoint, storage_access_key, storage_secret_key,'
echo '  tofu_state_bucket, tofu_state_region, tofu_state_endpoint,'
echo '  tofu_state_access_key, tofu_state_secret_key'
echo
echo "If TOFU_INPUTS_JSON is missing keys, tofu will fail at apply with"
echo "an 'undefined variable' error. Re-run with the missing keys added."
