***REMOVED***!/usr/bin/env bash
***REMOVED*** fetch_vault.sh — Pull deployment config from Bitwarden and render to:
***REMOVED***   1. .rendered/vault.env        — sourceable shell env vars (envsubst input)
***REMOVED***   2. .rendered/terraform.tfvars — tofu apply -var-file=
***REMOVED***   3. .rendered/runtime-config.json — Nix modules via builtins.fromJSON
***REMOVED***
***REMOVED*** Pattern inspired by ~/.local/share/devbox/global/default/bin/secrets-refresh:
***REMOVED***   - bw_sesh() wrapper (--session arg, env-var unreliable for auth)
***REMOVED***   - keyring auto-unlock via secret-tool (libsecret)
***REMOVED***   - atomic cache write (mktemp + mv) with chmod 600
***REMOVED***   - shell-safe quoting via printf %q
***REMOVED***
***REMOVED*** Bitwarden schema (vault `assistant`, items namespaced under that prefix):
***REMOVED***   "assistant/vps-access"     — Login, custom fields: host, ssh_user, ssh_port
***REMOVED***   "assistant/domain-config"  — Secure Note JSON:
***REMOVED***                                     {"domain":"<your-domain>","subdomains":["hermes",...]}
***REMOVED***   "assistant/tofu-inputs"    — Secure Note JSON (arbitrary TF_VAR_* keys)
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   scripts/fetch_vault.sh              ***REMOVED*** write all rendered outputs
***REMOVED***   scripts/fetch_vault.sh --check      ***REMOVED*** verify items exist; don't write
***REMOVED***   scripts/fetch_vault.sh --out-dir DIR  ***REMOVED*** custom output directory
***REMOVED***
***REMOVED*** Auto-unlock: if secret-tool (libsecret) is available and a Bitwarden master
***REMOVED*** password is stored in the keyring under "bitwarden master-password", this
***REMOVED*** script unlocks bw transparently and exports BW_SESSION. Otherwise set
***REMOVED*** BW_SESSION manually (`bw unlock --raw > ~/.bw_session_token`).
***REMOVED***
***REMOVED*** The fetched values flow through three sinks (vault.env, terraform.tfvars,
***REMOVED*** runtime-config.json). All three are gitignored and rebuilt on every run.
***REMOVED*** Bitwarden is the only place environment-specific values live.

set -euo pipefail

***REMOVED***--- arg parsing ----------------------------------------------------------------
CHECK_ONLY=0
OUT_DIR="${OUT_DIR:-.rendered}"
BW_SESSION="${BW_SESSION:-}"
BW_ORG_ID="${BW_ORG_ID:-}"   ***REMOVED*** empty = personal vault; set for org vault

while [[ $***REMOVED*** -gt 0 ]]; do
  case "$1" in
    --check)     CHECK_ONLY=1 ;;
    --out-dir)   OUT_DIR="$2"; shift ;;
    --session)   BW_SESSION="$2"; shift ;;
    --org-id)    BW_ORG_ID="$2"; shift ;;
    -h|--help)   sed -n '2,/^$/p' "$0" | sed 's/^***REMOVED*** \?//'; exit 0 ;;
    *)           echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

***REMOVED***--- preflight -----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { echo "missing required binary: $1" >&2; exit 1; }
}
need bw
need jq
need mkdir
need grep
need mktemp
need mv

***REMOVED***--- BW_SESSION resolution: keyring first, then env fallback --------------------
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
BW_SESSION not resolved. Two ways to fix:
  1. Recommended: store master password in system keyring once, then auto-unlock:
       secret-tool store --label="Bitwarden" bitwarden master-password
     (run \`scripts/fetch_vault.sh\` after that — it will auto-unlock from then on)
  2. One-off:
       bw unlock --raw > ~/.bw_session_token
       export BW_SESSION=\$(cat ~/.bw_session_token)
EOF
    exit 1
  }

***REMOVED*** bw_sesh wrapper. bw's daemon ignores BW_SESSION env for auth-state checks; every
***REMOVED*** call must pass --session explicitly. (Same lesson as devbox secrets-refresh.)
bw_sesh() { bw --session "$BW_SESSION" "$@"; }

***REMOVED***--- helpers -------------------------------------------------------------------
***REMOVED*** Pull a single custom-field value from a Login item by name.
fetch_login_field() {
  local item_name="$1" field_name="$2"
  if [[ -n "$BW_ORG_ID" ]]; then
    bw_sesh list items --organizationid "$BW_ORG_ID" 2>/dev/null \
      | jq -r --arg n "$item_name" --arg f "$field_name" \
        '.[] | select(.type == 1 and .name == $n) | .fields[]? | select(.name == $f) | .value' \
      | head -n1
  else
    bw_sesh list items 2>/dev/null \
      | jq -r --arg n "$item_name" --arg f "$field_name" \
        '.[] | select(.type == 1 and .name == $n) | .fields[]? | select(.name == $f) | .value' \
      | head -n1
  fi
}

***REMOVED*** Pull the JSON payload of a Secure Note item by name.
fetch_note_payload() {
  local item_name="$1"
  if [[ -n "$BW_ORG_ID" ]]; then
    bw_sesh list items --organizationid "$BW_ORG_ID" 2>/dev/null \
      | jq -r --arg n "$item_name" \
        '.[] | select(.type == 2 and .name == $n) | .notes // ""'
  else
    bw_sesh list items 2>/dev/null \
      | jq -r --arg n "$item_name" \
        '.[] | select(.type == 2 and .name == $n) | .notes // ""'
  fi
}

assert_non_empty() {
  local label="$1" value="$2"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "Bitwarden field empty: $label" >&2
    echo "  check items 'assistant/vps-access', 'assistant/domain-config', 'assistant/tofu-inputs'" >&2
    exit 1
  fi
}

ensure_gitignored() {
  ***REMOVED*** Fail-closed: refuse to write if .gitignore is missing — prevents accidental
  ***REMOVED*** commit of a rendered file with real values.
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

***REMOVED***--- main fetch ----------------------------------------------------------------
ITEM_VPS='assistant/vps-access'
ITEM_DOMAIN='assistant/domain-config'
ITEM_TOFU='assistant/tofu-inputs'

***REMOVED*** VPS Access (Login → 3 custom fields)
VPS_HOST="$(fetch_login_field "$ITEM_VPS" host)"
VPS_SSH_USER="$(fetch_login_field "$ITEM_VPS" ssh_user)"
VPS_SSH_PORT="$(fetch_login_field "$ITEM_VPS" ssh_port)"
assert_non_empty "$ITEM_VPS.host"     "$VPS_HOST"
assert_non_empty "$ITEM_VPS.ssh_user" "$VPS_SSH_USER"
assert_non_empty "$ITEM_VPS.ssh_port" "$VPS_SSH_PORT"

***REMOVED*** Domain Config (Secure Note → JSON body)
DOMAIN_JSON="$(fetch_note_payload "$ITEM_DOMAIN")"
[[ -n "$DOMAIN_JSON" ]] || { echo "$ITEM_DOMAIN note body empty" >&2; exit 1; }
echo "$DOMAIN_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "$ITEM_DOMAIN body is not valid JSON: $DOMAIN_JSON" >&2; exit 1; }

DOMAIN="$(echo "$DOMAIN_JSON" | jq -r '.domain')"
SUBDOMAINS_JSON="$(echo "$DOMAIN_JSON" | jq -c '.subdomains')"
SUBDOMAINS_CSV="$(echo "$DOMAIN_JSON" | jq -r '.subdomains | join(",")')"
assert_non_empty "$ITEM_DOMAIN.domain"     "$DOMAIN"
assert_non_empty "$ITEM_DOMAIN.subdomains" "$SUBDOMAINS_JSON"

***REMOVED*** Tofu Inputs (Secure Note → JSON body, optional)
TOFU_JSON="$(fetch_note_payload "$ITEM_TOFU" 2>/dev/null || true)"
[[ -z "$TOFU_JSON" ]] && TOFU_JSON='{}'
echo "$TOFU_JSON" | jq -e . >/dev/null 2>&1 \
  || { echo "$ITEM_TOFU body is not valid JSON: $TOFU_JSON" >&2; exit 1; }

if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "fetch_vault --check: all items present."
  echo "  VPS:    $VPS_SSH_USER@$VPS_HOST:$VPS_SSH_PORT"
  echo "  DOMAIN: $DOMAIN  SUBDOMAINS: $SUBDOMAINS_CSV"
  exit 0
fi

***REMOVED***--- render --------------------------------------------------------------------
mkdir -p "$OUT_DIR"

ENV_FILE="$OUT_DIR/vault.env"
TFVARS_FILE="$OUT_DIR/terraform.tfvars"
RUNTIME_JSON="$OUT_DIR/runtime-config.json"

***REMOVED*** Pre-register outputs in .gitignore (idempotent, fail-closed).
for f in "$ENV_FILE" "$TFVARS_FILE" "$RUNTIME_JSON"; do
  ensure_gitignored "$(to_relpath "$f")"
done

***REMOVED*** vault.env: sourceable shell exports. %q handles shell quoting for free.
tmp="$(mktemp)"
{
  printf '***REMOVED*** GENERATED by scripts/fetch_vault.sh — DO NOT EDIT OR COMMIT\n'
  printf '***REMOVED*** Regenerate at deploy time: scripts/fetch_vault.sh\n\n'
  printf 'export %s=%q\n' VPS_HOST     "$VPS_HOST"
  printf 'export %s=%q\n' VPS_SSH_USER "$VPS_SSH_USER"
  printf 'export %s=%q\n' VPS_SSH_PORT "$VPS_SSH_PORT"
  printf 'export %s=%q\n' DOMAIN       "$DOMAIN"
  printf 'export %s=%q\n' SUBDOMAINS_JSON "$SUBDOMAINS_JSON"

  ***REMOVED*** Export arbitrary TF_VAR_* from Tofu Inputs JSON.
  echo "$TOFU_JSON" | jq -r '
    to_entries[]
    | "export TF_VAR_\(.key | ascii_upcase)=\(.value | tostring)"
  '

  ***REMOVED*** Export selected non-TF vars from Tofu Inputs for envsubst / deploy scripts.
  ***REMOVED*** These are also written to terraform.tfvars below as Tofu variables.
  ***REMOVED*** Includes TOFU_STATE_* keys consumed by tofu/tofu-wrapper.sh for the S3 backend.
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
} > "$tmp"
mv "$tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"

***REMOVED*** terraform.tfvars: passed to tofu via -var-file=.rendered/terraform.tfvars.
tmp="$(mktemp)"
{
  printf '***REMOVED*** GENERATED by scripts/fetch_vault.sh — DO NOT EDIT OR COMMIT\n'
  printf '***REMOVED*** Regenerate at deploy time. Pass to tofu via:\n'
  printf '***REMOVED***   tofu apply -var-file=.rendered/terraform.tfvars\n\n'
  printf 'domain_name = %s\n' "$(jq -Rn --arg v "$DOMAIN" '$v')"
  printf 'ssh_user    = %s\n' "$(jq -Rn --arg v "$VPS_SSH_USER" '$v')"
  printf 'vps_ip      = %s\n' "$(jq -Rn --arg v "$VPS_HOST" '$v')"
  printf 'ssh_port    = %d\n' "$VPS_SSH_PORT"
  printf 'subdomains  = %s\n' "$SUBDOMAINS_JSON"

  ***REMOVED*** Append any extra Tofu Inputs as tfvars — keys map verbatim (caller has
  ***REMOVED*** already declared matching variables in tofu/variables.tf).
  ***REMOVED*** Exclude TOFU_STATE_* keys; those are consumed by tofu-wrapper.sh from env vars,
  ***REMOVED*** not passed as Tofu input variables.
  echo "$TOFU_JSON" | jq -r '
    to_entries[]
    | select(.key != "domain_name" and .key != "ssh_user" and .key != "vps_ip"
             and .key != "ssh_port" and .key != "subdomains"
             and .key != "tofu_state_bucket" and .key != "tofu_state_region"
             and .key != "tofu_state_endpoint" and .key != "tofu_state_access_key"
             and .key != "tofu_state_secret_key")
    | "\(.key) = \(.value | tostring)"
  '
} > "$tmp"
mv "$tmp" "$TFVARS_FILE"
chmod 600 "$TFVARS_FILE"

***REMOVED*** runtime-config.json: read by Nix modules via builtins.fromJSON
***REMOVED*** (Option A per prior Oracle review — gitignored file visible via `path:` flakeref).
jq -n \
  --arg domain "$DOMAIN" \
  --arg vps_host "$VPS_HOST" \
  --arg ssh_user "$VPS_SSH_USER" \
  --argjson ssh_port "$VPS_SSH_PORT" \
  --argjson subdomains "$SUBDOMAINS_JSON" \
  --argjson tofu "$TOFU_JSON" \
  '{
     domain:     $domain,
     subdomains: $subdomains,
     vps_host:   $vps_host,
     ssh_user:   $ssh_user,
     ssh_port:   $ssh_port,
     tofu:       $tofu
   }' \
  > "$RUNTIME_JSON"
chmod 600 "$RUNTIME_JSON"

***REMOVED***--- summary -------------------------------------------------------------------
echo
echo "fetch_vault: rendered."
echo "  VPS:    $VPS_SSH_USER@$VPS_HOST:$VPS_SSH_PORT"
echo "  DOMAIN: $DOMAIN"
echo "  SUBS:   $SUBDOMAINS_CSV"
echo "  env:    $ENV_FILE"
echo "  tfvars: $TFVARS_FILE"
echo "  nix:    $RUNTIME_JSON"
echo
echo "Next steps:"
echo "  source $ENV_FILE                       ***REMOVED*** loads VPS_HOST, DOMAIN, etc."
echo "  tofu apply -var-file=$TFVARS_FILE      ***REMOVED*** Tofu with vault-driven inputs"
echo "  nixos-rebuild build --flake path:\$NIX_CONFIG_DIR***REMOVED***agent  ***REMOVED*** Nix reads runtime-config.json"
