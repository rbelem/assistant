#!/usr/bin/env bash
# bws.sh — helper library for Bitwarden Secrets Manager (official CLI)
#
# Usage in scripts:
#   source "$(dirname "$0")/lib/bws.sh"
#   bws_get "VPS_SSH_KEY"       # get value by key
#
# The BWS_ACCESS_TOKEN env var or ~/.config/bitw/config (key: sm_access_token)
# must be configured first.

set -euo pipefail

#--- constants ------------------------------------------------------------------
# The `assistant` SM project UUID (resolved once at first use)
_BWS_PROJECT_ID=""

#--- helpers --------------------------------------------------------------------
# Load BWS_ACCESS_TOKEN from env, else from ~/.config/bitw/config (key: sm_access_token).
# The config file may contain lines like `sm_access_token=...` or `export sm_access_token=...`.
_bws_load_token() {
  if [[ -n "${BWS_ACCESS_TOKEN:-}" ]]; then
    return 0
  fi
  local cfg="${BWS_CONFIG_FILE:-$HOME/.config/bitw/config}"
  [[ -f "$cfg" ]] || return 0
  local line
  line="$(grep -E '^[[:space:]]*(export[[:space:]]+)?sm_access_token[[:space:]]*=' "$cfg" | head -n1 || true)"
  [[ -n "$line" ]] || return 0
  BWS_ACCESS_TOKEN="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?sm_access_token[[:space:]]*=[[:space:]]*//; s/^"//; s/"$//')"
  export BWS_ACCESS_TOKEN
}

_bws_resolve_project() {
  _bws_load_token
  if [[ -z "$_BWS_PROJECT_ID" ]]; then
    _BWS_PROJECT_ID="$(bws project list -o json 2>/dev/null \
      | jq -r '.[] | select(.name == "assistant") | .id')"
    if [[ -z "$_BWS_PROJECT_ID" || "$_BWS_PROJECT_ID" == "null" ]]; then
      echo "bws: assistant project not found in SM" >&2
      return 1
    fi
  fi
  echo "$_BWS_PROJECT_ID"
}

#--- public API -----------------------------------------------------------------

# bws_get <key> — fetch a single secret value by key name.
# Returns the raw value (may be multi-line, binary-safe via jq).
# Returns 1 (non-zero) if the key is missing or empty.
bws_get() {
  local key="$1" pid val
  pid="$(_bws_resolve_project)"
  val="$(bws secret list -o json "$pid" 2>/dev/null \
    | jq -r --arg k "$key" '.[] | select(.key == $k) | .value')"
  if [[ -z "$val" || "$val" == "null" ]]; then
    return 1
  fi
  printf '%s' "$val"
}

# bws_get_all — return all secrets as JSON array (for caching / batch processing).
# Usage: bws_get_all | jq -r '.[] | select(.key == "VPS_SSH_KEY") | .value'
bws_get_all() {
  local pid
  pid="$(_bws_resolve_project)"
  bws secret list -o json "$pid" 2>/dev/null
}

# bws_list — list all secrets in table format (human-readable).
bws_list() {
  local pid
  pid="$(_bws_resolve_project)"
  bws secret list -o table "$pid" 2>/dev/null
}

# bws_create <key> <value> — create a new secret.
# Handles values starting with `-` by creating a placeholder then editing.
bws_create() {
  local key="$1" value="$2"
  local pid
  pid="$(_bws_resolve_project)"

  if [[ "$value" == -* ]]; then
    # Value starts with dash — create placeholder, then edit
    local created_id
    created_id="$(bws secret create "$key" "__bws_placeholder" "$pid" 2>/dev/null \
      | jq -r '.id')"
    if [[ -z "$created_id" || "$created_id" == "null" ]]; then
      echo "bws_create: failed to create placeholder for $key" >&2
      return 1
    fi
    if ! bws secret edit "--value=$value" "$created_id" 2>/dev/null; then
      # Don't leave the placeholder behind if the edit fails
      bws secret delete "$created_id" >/dev/null 2>&1 || true
      echo "bws_create: failed to set value for $key (placeholder removed)" >&2
      return 1
    fi
  else
    bws secret create "$key" "$value" "$pid" 2>/dev/null
  fi
}

# bws_assert <key> — verify a secret exists and is non-empty.
# Used for preflight checks.
bws_assert() {
  local key="$1"
  local val
  val="$(bws_get "$key")"
  if [[ -z "$val" ]]; then
    echo "bws_assert: SM secret '$key' is empty or not found" >&2
    return 1
  fi
}

# bws_check — verify SM access token works. Usage: bws_check || exit 1
bws_check() {
  _bws_load_token
  if ! bws project list >/dev/null 2>&1; then
    echo "bws: SM access token missing or invalid" >&2
    echo "  Export BWS_ACCESS_TOKEN or set in ~/.config/bitw/config" >&2
    return 1
  fi
}