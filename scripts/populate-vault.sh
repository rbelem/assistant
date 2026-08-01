#!/usr/bin/env bash
# populate-vault.sh — Create the 3 Bitwarden items needed for the
# Bitwarden+template externalization architecture. Idempotent: skips items
# that already exist.
#
# Uses the `bitw` CLI (rbelem fork). bitw auto-unlocks via libsecret keyring
# (entry "bitwarden master-password"), or the PASSWORD env var, or an
# interactive prompt. No session tokens, no BW_SESSION.
#
# Required env vars:
#   VPS_HOST          — current VPS public IPv4
#   DOMAIN            — base domain (e.g. example.com)
#   SUBDOMAINS_JSON   — JSON array (e.g. '["app","www"]')
#   PROJECT_NAME      — project prefix (e.g. assistant)
#   TOFU_INPUTS_JSON  — JSON object with Tofu vars (plan, datacenter, etc.)
#   SSH_PRIVATE_KEY   — SSH private key (PEM format)
#   SSH_PUBLIC_KEY    — SSH public key (e.g. ssh-ed25519 AAAA...)
#
# Optional env vars (with defaults):
#   SSH_USER          — SSH user (default: root)
#   SSH_PORT          — SSH port (default: 22)
#
# Usage:
#   VPS_HOST=203.0.113.42 DOMAIN=example.com \
#     PROJECT_NAME=assistant \
#     SUBDOMAINS_JSON='["app","www"]' \
#     TOFU_INPUTS_JSON='{"vps_plan_code":"KVM 4","datacenter":"gra","vps_image_id":"...","state_bucket_name":"...-tofu-state","storage_region":"gra","storage_endpoint":"https://s3.gra.io.REDACTED-OVH-DOMAIN","storage_access_key":"...","storage_secret_key":"...","ssh_public_key":"...","vps_os":"debian-12","vps_display_name":"agent"}' \
#     scripts/populate-vault.sh
#
# After successful run: scripts/fetch_vault.sh --check  # validate schema

set -euo pipefail

#--- arg validation ------------------------------------------------------------
: "${VPS_HOST:?must set VPS_HOST (VPS public IPv4)}"
: "${DOMAIN:?must set DOMAIN (e.g. example.com)}"
: "${SUBDOMAINS_JSON:?must set SUBDOMAINS_JSON (JSON array string)}"
: "${PROJECT_NAME:?must set PROJECT_NAME (e.g. assistant)}"
: "${TOFU_INPUTS_JSON:?must set TOFU_INPUTS_JSON (JSON object)}"
: "${SSH_PRIVATE_KEY:?must set SSH_PRIVATE_KEY (PEM format)}"
: "${SSH_PUBLIC_KEY:?must set SSH_PUBLIC_KEY (e.g. ssh-ed25519 AAAA...)}"

SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"

#--- preflight ----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { echo "missing required binary: $1" >&2; exit 1; }
}
need bitw
need jq

# Validate JSON payloads up front
echo "$SUBDOMAINS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "SUBDOMAINS_JSON is not valid JSON: $SUBDOMAINS_JSON" >&2; exit 1; }
echo "$TOFU_INPUTS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "TOFU_INPUTS_JSON is not valid JSON: $TOFU_INPUTS_JSON" >&2; exit 1; }

#--- bitw preflight: verify login tokens exist --------------------------------
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

#--- item 1: assistant/vps-ssh-key (SSH key type) -----------------------------
echo
echo "Creating assistant/vps-ssh-key (SSH key type)..."
if bitw get --json "assistant/vps-ssh-key" >/dev/null 2>&1; then
  echo "  ⊘ assistant/vps-ssh-key (already exists — skip)"
else
  # Private key via stdin to avoid argv exposure
  if ! printf '%s' "$SSH_PRIVATE_KEY" | bitw create --type 5 --ssh-private-key-stdin --ssh-public-key "$SSH_PUBLIC_KEY" "assistant/vps-ssh-key"; then
    echo "  ✗ assistant/vps-ssh-key: bitw create failed" >&2
    exit 1
  fi
  echo "  ✓ assistant/vps-ssh-key (created)"
fi

#--- item 2: assistant/domain-config (Secure Note + JSON) ------------------
echo
echo "Creating assistant/domain-config (Secure Note)..."
if bitw get --json "assistant/domain-config" >/dev/null 2>&1; then
  echo "  ⊘ assistant/domain-config (already exists — skip)"
else
  DOMAIN_NOTES="$(jq -n --arg domain "$DOMAIN" --argjson subdomains "$SUBDOMAINS_JSON" '{domain:$domain, subdomains:$subdomains}' | jq -c .)"
  if ! bitw create --type 2 --notes "$DOMAIN_NOTES" "assistant/domain-config"; then
    echo "  ✗ assistant/domain-config: bitw create failed" >&2
    exit 1
  fi
  echo "  ✓ assistant/domain-config (created)"
fi

#--- item 3: assistant/tofu-inputs (Secure Note + JSON) --------------------
echo
echo "Creating assistant/tofu-inputs (Secure Note)..."
if bitw get --json "assistant/tofu-inputs" >/dev/null 2>&1; then
  echo "  ⊘ assistant/tofu-inputs (already exists — skip)"
else
  TOFU_NOTES="$(jq -n --argjson inputs "$TOFU_INPUTS_JSON" --arg project "$PROJECT_NAME" --arg domain "$DOMAIN" --arg host "$VPS_HOST" --arg user "$SSH_USER" --argjson port "$SSH_PORT" '{project_name:$project, domain:$domain, vps_host:$host, vps_ssh_user:$user, vps_ssh_port:$port} + $inputs' | jq -c .)"
  if ! bitw create --type 2 --notes "$TOFU_NOTES" "assistant/tofu-inputs"; then
    echo "  ✗ assistant/tofu-inputs: bitw create failed" >&2
    exit 1
  fi
  echo "  ✓ assistant/tofu-inputs (created)"
fi

#--- verify -------------------------------------------------------------------
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

#--- summary ------------------------------------------------------------------
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
