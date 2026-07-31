***REMOVED***!/usr/bin/env bash
***REMOVED*** populate-vault.sh — Create the 3 Bitwarden items needed for the
***REMOVED*** Bitwarden+template externalization architecture. Idempotent: skips items
***REMOVED*** that already exist.
***REMOVED***
***REMOVED*** Uses the `bitw` CLI (rbelem fork). bitw auto-unlocks via libsecret keyring
***REMOVED*** (entry "bitwarden master-password"), or the PASSWORD env var, or an
***REMOVED*** interactive prompt. No session tokens, no BW_SESSION.
***REMOVED***
***REMOVED*** Required env vars:
***REMOVED***   VPS_HOST          — current VPS public IPv4
***REMOVED***   DOMAIN            — base domain (e.g. example.com)
***REMOVED***   SUBDOMAINS_JSON   — JSON array (e.g. '["app","www"]')
***REMOVED***   PROJECT_NAME      — project prefix (e.g. assistant)
***REMOVED***   TOFU_INPUTS_JSON  — JSON object with Tofu vars (plan, datacenter, etc.)
***REMOVED***   SSH_PRIVATE_KEY   — SSH private key (PEM format)
***REMOVED***   SSH_PUBLIC_KEY    — SSH public key (e.g. ssh-ed25519 AAAA...)
***REMOVED***
***REMOVED*** Optional env vars (with defaults):
***REMOVED***   SSH_USER          — SSH user (default: root)
***REMOVED***   SSH_PORT          — SSH port (default: 22)
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   VPS_HOST=203.0.113.42 DOMAIN=example.com \
***REMOVED***     PROJECT_NAME=assistant \
***REMOVED***     SUBDOMAINS_JSON='["app","www"]' \
***REMOVED***     TOFU_INPUTS_JSON='{"vps_plan_code":"KVM 4","datacenter":"gra","vps_image_id":"...","state_bucket_name":"...-tofu-state","storage_region":"gra","storage_endpoint":"https://s3.gra.io.REDACTED-OVH-DOMAIN","storage_access_key":"...","storage_secret_key":"...","ssh_public_key":"...","vps_os":"debian-12","vps_display_name":"agent"}' \
***REMOVED***     scripts/populate-vault.sh
***REMOVED***
***REMOVED*** After successful run: scripts/fetch_vault.sh --check  ***REMOVED*** validate schema

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
need bitw
need jq

***REMOVED*** Validate JSON payloads up front
echo "$SUBDOMAINS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "SUBDOMAINS_JSON is not valid JSON: $SUBDOMAINS_JSON" >&2; exit 1; }
echo "$TOFU_INPUTS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "TOFU_INPUTS_JSON is not valid JSON: $TOFU_INPUTS_JSON" >&2; exit 1; }

***REMOVED***--- bitw preflight: verify login tokens exist --------------------------------
if ! bitw status 2>/dev/null | grep -q 'token_valid.*valid'; then
  cat >&2 <<EOF
bitw login tokens not found. Two options:
  1. Run \`bitw login\` (interactive) to store login tokens.
  2. Store master password in keyring for auto-unlock:
       secret-tool store --label="Bitwarden" bitwarden master-password
     (bitw will use it automatically from then on)
EOF
  exit 1
fi

***REMOVED***--- item 1: assistant/vps-ssh-key (SSH key type) -----------------------------
echo
echo "Creating assistant/vps-ssh-key (SSH key type)..."
if bitw get --json "assistant/vps-ssh-key" >/dev/null 2>&1; then
  echo "  ⊘ assistant/vps-ssh-key (already exists — skip)"
else
  ***REMOVED*** Private key via stdin to avoid argv exposure
  if ! printf '%s' "$SSH_PRIVATE_KEY" | bitw create "assistant/vps-ssh-key" --type 5 --ssh-private-key-stdin --ssh-public-key "$SSH_PUBLIC_KEY"; then
    echo "  ✗ assistant/vps-ssh-key: bitw create failed" >&2
    exit 1
  fi
  echo "  ✓ assistant/vps-ssh-key (created)"
fi

***REMOVED***--- item 2: assistant/domain-config (Secure Note + JSON) ------------------
echo
echo "Creating assistant/domain-config (Secure Note)..."
if bitw get --json "assistant/domain-config" >/dev/null 2>&1; then
  echo "  ⊘ assistant/domain-config (already exists — skip)"
else
  DOMAIN_NOTES="$(jq -n --arg domain "$DOMAIN" --argjson subdomains "$SUBDOMAINS_JSON" '{domain:$domain, subdomains:$subdomains}' | jq -c .)"
  if ! bitw create "assistant/domain-config" --type 2 --notes "$DOMAIN_NOTES"; then
    echo "  ✗ assistant/domain-config: bitw create failed" >&2
    exit 1
  fi
  echo "  ✓ assistant/domain-config (created)"
fi

***REMOVED***--- item 3: assistant/tofu-inputs (Secure Note + JSON) --------------------
echo
echo "Creating assistant/tofu-inputs (Secure Note)..."
if bitw get --json "assistant/tofu-inputs" >/dev/null 2>&1; then
  echo "  ⊘ assistant/tofu-inputs (already exists — skip)"
else
  TOFU_NOTES="$(jq -n --argjson inputs "$TOFU_INPUTS_JSON" --arg project "$PROJECT_NAME" --arg domain "$DOMAIN" --arg host "$VPS_HOST" --arg user "$SSH_USER" --argjson port "$SSH_PORT" '{project_name:$project, domain:$domain, vps_host:$host, vps_ssh_user:$user, vps_ssh_port:$port} + $inputs' | jq -c .)"
  if ! bitw create "assistant/tofu-inputs" --type 2 --notes "$TOFU_NOTES"; then
    echo "  ✗ assistant/tofu-inputs: bitw create failed" >&2
    exit 1
  fi
  echo "  ✓ assistant/tofu-inputs (created)"
fi

***REMOVED***--- verify -------------------------------------------------------------------
echo
echo "Verifying items are retrievable..."
all_ok=1
for name in assistant/vps-ssh-key assistant/domain-config assistant/tofu-inputs; do
  if bitw get --json "$name" >/dev/null 2>&1; then
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
echo "To update values later, edit the items in Bitwarden or via bitw CLI:"
echo "  bitw get --json 'assistant/tofu-inputs' | jq -r '.notes | fromjson'"
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
