***REMOVED***!/usr/bin/env bash
***REMOVED*** populate-sm.sh — Create the Secrets Manager keys needed for the
***REMOVED*** Bitwarden SM+template externalization architecture. Idempotent: skips
***REMOVED*** keys that already exist.
***REMOVED***
***REMOVED*** Uses the `bws` CLI (official Bitwarden Secrets Manager CLI).
***REMOVED*** Authentication is via a machine-account access token — no
***REMOVED*** master password, no interactive login. Set BWS_ACCESS_TOKEN env or store
***REMOVED*** the token in ~/.config/bitw/config (key: sm_access_token).
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
***REMOVED***     scripts/populate-sm.sh
***REMOVED***
***REMOVED*** After successful run: scripts/fetch_vault.sh --check  ***REMOVED*** validate schema

set -euo pipefail
source "$(dirname "$0")/lib/bws.sh"

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
need bws
need jq

***REMOVED*** Validate JSON payloads up front
echo "$SUBDOMAINS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "SUBDOMAINS_JSON is not valid JSON: $SUBDOMAINS_JSON" >&2; exit 1; }
echo "$TOFU_INPUTS_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "TOFU_INPUTS_JSON is not valid JSON: $TOFU_INPUTS_JSON" >&2; exit 1; }

***REMOVED***--- SM preflight: verify Secrets Manager access token -------------------------
bws_check || exit 1

***REMOVED***--- helper: create SM secret idempotently -------------------------------------
***REMOVED*** If `bws_get <key>` succeeds, the secret exists → skip.
***REMOVED*** Otherwise, create it with `bws_create <key> <value>`.
sm_create_if_missing() {
  local key="$1" value="$2"
  if bws_get "$key" >/dev/null 2>&1; then
    echo "  ⊘ $key (already exists — skip)"
    return 0
  fi
  if ! bws_create "$key" "$value" 2>/dev/null; then
    echo "  ✗ $key: bws_create failed" >&2
    return 1
  fi
  echo "  ✓ $key (created)"
}

***REMOVED***--- key 1: VPS_SSH_KEY (SSH private key, raw) ----------------------
echo
echo "Creating VPS_SSH_KEY (SSH private key)..."
sm_create_if_missing "VPS_SSH_KEY" "$SSH_PRIVATE_KEY" \
  || exit 1

***REMOVED***--- key 2: DOMAIN_CONFIG (JSON) ------------------------------------
echo
echo "Creating DOMAIN_CONFIG (JSON)..."
DOMAIN_JSON="$(jq -n --arg domain "$DOMAIN" --argjson subdomains "$SUBDOMAINS_JSON" '{domain:$domain, subdomains:$subdomains}' | jq -c .)"
sm_create_if_missing "DOMAIN_CONFIG" "$DOMAIN_JSON" \
  || exit 1

***REMOVED***--- key 3: TOFU_INPUTS (JSON) --------------------------------------
echo
echo "Creating TOFU_INPUTS (JSON)..."
TOFU_JSON="$(jq -n --argjson inputs "$TOFU_INPUTS_JSON" --arg project "$PROJECT_NAME" --arg domain "$DOMAIN" --arg host "$VPS_HOST" --arg user "$SSH_USER" --argjson port "$SSH_PORT" '{project_name:$project, domain:$domain, vps_host:$host, vps_ssh_user:$user, vps_ssh_port:$port} + $inputs' | jq -c .)"
sm_create_if_missing "TOFU_INPUTS" "$TOFU_JSON" \
  || exit 1

***REMOVED***--- verify -------------------------------------------------------------------
echo
echo "Verifying SM keys are retrievable..."
all_ok=1
for key in VPS_SSH_KEY DOMAIN_CONFIG TOFU_INPUTS; do
  if bws_get "$key" >/dev/null 2>&1; then
    echo "  ✓ $key retrievable"
  else
    echo "  ✗ $key NOT retrievable" >&2
    all_ok=0
  fi
done

[[ "$all_ok" == "1" ]] || { echo "Verification failed." >&2; exit 1; }

***REMOVED***--- summary ------------------------------------------------------------------
echo
echo "All 3 SM keys created/verified."
echo
echo "Next step: validate the schema + render end-to-end:"
echo "  scripts/fetch_vault.sh --check"
echo
echo "To update values later:"
echo "  bws_get 'TOFU_INPUTS'   ***REMOVED*** read current value (via lib/bws.sh)"
echo "  bws secret edit <ID> --value='...'  ***REMOVED*** update value (raw CLI)"
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
