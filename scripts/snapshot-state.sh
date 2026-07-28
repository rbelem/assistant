#!/usr/bin/env bash
# snapshot-state.sh — defensive backup of tofu state to Bitwarden
#
# Reads the current .tfstate from the live S3 backend, base64-encodes it,
# and appends it to a history chain in assistant/tofu-state-snapshot (BW
# Secure Note). Trims to SNAPSHOT_HISTORY_MAX entries (default 10) to keep
# note size bounded. Captures backend URL + git SHA for cross-reference.
#
# Usage:
#   scripts/snapshot-state.sh              # snapshot current state
#   scripts/snapshot-state.sh --help       # this message
#
# Environment:
#   BW_SESSION              required (bw unlock --raw)
#   SNAPSHOT_BW_ITEM        BW item name (default: assistant/tofu-state-snapshot)
#   SNAPSHOT_HISTORY_MAX    max snapshots to keep (default: 10)
#   TOFU_DIR                path to tofu/ directory (default: ../tofu relative to script)
#
# Exit codes:
#   0  success
#   1  usage error
#   2  BW unavailable
#   3  item missing
#   4  tofu state pull failed
#   5  bw write failed

set -euo pipefail

#--- exit codes ----------------------------------------------------------------
readonly EXIT_USAGE=1
readonly EXIT_BW_UNAVAILABLE=2
readonly EXIT_ITEM_MISSING=3
readonly EXIT_TOFU_FAILED=4
readonly EXIT_BW_WRITE_FAILED=5

#--- config --------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_BW_ITEM="${SNAPSHOT_BW_ITEM:-assistant/tofu-state-snapshot}"
SNAPSHOT_HISTORY_MAX="${SNAPSHOT_HISTORY_MAX:-10}"
TOFU_DIR="${TOFU_DIR:-$REPO_ROOT/tofu}"

#--- colors + helpers ----------------------------------------------------------
if [[ -t 2 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info()  { echo -e "${BLUE}:: $*${NC}" >&2; }
ok()    { echo -e "${GREEN}✓  $*${NC}" >&2; }
warn()  { echo -e "${YELLOW}!  $*${NC}" >&2; }
err()   { echo -e "${RED}✗ $*${NC}" >&2; }

#--- arg parsing ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)          err "unknown arg: $1"; exit "$EXIT_USAGE" ;;
  esac
  # shellcheck disable=SC2317  # shift is reachable if case branches are added
  shift
done

#--- preflight -----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { err "missing required binary: $1"; exit "$EXIT_USAGE"; }
}
need bw
need jq
need python3
need base64

# BW_SESSION resolution: env first, then keyring auto-unlock (same pattern as fetch_vault.sh)
BW_SESSION="${BW_SESSION:-}"
if [[ -z "$BW_SESSION" ]] && command -v secret-tool >/dev/null 2>&1; then
  if master_pw="$(secret-tool lookup bitwarden master-password 2>/dev/null)" \
     && [[ -n "$master_pw" ]]; then
    if BW_SESSION="$(bw unlock --raw "$master_pw" 2>/dev/null)" \
       && [[ -n "$BW_SESSION" ]]; then
      export BW_SESSION
    fi
    unset master_pw
  fi
fi

[[ -n "$BW_SESSION" ]] \
  || { err "BW_SESSION not set. Run: bw unlock --raw > ~/.bw_session_token && export BW_SESSION=\$(cat ~/.bw_session_token)"; exit "$EXIT_BW_UNAVAILABLE"; }

bw_sesh() { bw --session "$BW_SESSION" "$@"; }

# Sync vault cache (idempotent, fast)
bw_sesh sync 2>/dev/null || true

# Verify BW session is valid
if ! bw_sesh list items >/dev/null 2>&1; then
  err "bw session invalid or expired"
  exit "$EXIT_BW_UNAVAILABLE"
fi

#--- detect backend URL --------------------------------------------------------
# Try .rendered/backend.conf first (materialized by tofu-wrapper.sh), then fall
# back to parsing tofu state metadata if available.
BACKEND_URL=""
if [[ -f "$REPO_ROOT/.rendered/backend.conf" ]]; then
  # Extract endpoint + bucket from backend.conf
  endpoint="$(grep -E '^\s*endpoint\s*=' "$REPO_ROOT/.rendered/backend.conf" | sed 's/.*=\s*"\(.*\)"/\1/' || true)"
  bucket="$(grep -E '^\s*bucket\s*=' "$REPO_ROOT/.rendered/backend.conf" | sed 's/.*=\s*"\(.*\)"/\1/' || true)"
  if [[ -n "$endpoint" && -n "$bucket" ]]; then
    BACKEND_URL="s3://${bucket}@${endpoint}"
  fi
fi

#--- get git SHA ---------------------------------------------------------------
ASSISTANT_REPO_SHA=""
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  ASSISTANT_REPO_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
fi

#--- pull tofu state -----------------------------------------------------------
info "pulling tofu state from $TOFU_DIR..."
if [[ ! -d "$TOFU_DIR" ]]; then
  err "tofu directory not found: $TOFU_DIR"
  exit "$EXIT_TOFU_FAILED"
fi

# tofu state pull requires the backend to be initialized. If .terraform doesn't
# exist, we can't pull. (Operator should run `tofu init` first.)
if [[ ! -d "$TOFU_DIR/.terraform" ]]; then
  err "tofu backend not initialized. Run: cd $TOFU_DIR && tofu init"
  exit "$EXIT_TOFU_FAILED"
fi

STATE_JSON=""
if ! STATE_JSON="$(tofu -chdir="$TOFU_DIR" state pull -no-color 2>&1)"; then
  err "tofu state pull failed:"
  echo "$STATE_JSON" >&2
  exit "$EXIT_TOFU_FAILED"
fi

# Validate it's JSON
if ! echo "$STATE_JSON" | jq -e . >/dev/null 2>&1; then
  err "tofu state pull returned invalid JSON"
  exit "$EXIT_TOFU_FAILED"
fi

STATE_BYTE_SIZE="${#STATE_JSON}"
STATE_B64="$(echo "$STATE_JSON" | base64 -w 0)"
TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

ok "pulled state: $STATE_BYTE_SIZE bytes"

#--- build snapshot entry ------------------------------------------------------
SNAPSHOT_ENTRY="$(jq -n \
  --argjson schema_version 1 \
  --arg timestamp_utc "$TIMESTAMP_UTC" \
  --arg backend "$BACKEND_URL" \
  --arg assistant_repo_sha "$ASSISTANT_REPO_SHA" \
  --arg state_b64 "$STATE_B64" \
  --argjson byte_size "$STATE_BYTE_SIZE" \
  '{
    schema_version: $schema_version,
    timestamp_utc: $timestamp_utc,
    backend: $backend,
    assistant_repo_sha: $assistant_repo_sha,
    state_b64: $state_b64,
    byte_size: $byte_size
  }')"

#--- read existing BW item (if exists) -----------------------------------------
info "reading existing snapshot item: $SNAPSHOT_BW_ITEM..."
EXISTING_ITEM_JSON=""
EXISTING_ITEM_ID=""
if EXISTING_ITEM_JSON="$(bw_sesh get item "$SNAPSHOT_BW_ITEM" 2>/dev/null)"; then
  EXISTING_ITEM_ID="$(echo "$EXISTING_ITEM_JSON" | jq -r '.id')"
  info "found existing item (id: $EXISTING_ITEM_ID)"
else
  warn "item not found: $SNAPSHOT_BW_ITEM"
  err "Create it first with:"
  err "  bw create item --type 2 --name '$SNAPSHOT_BW_ITEM' --notes '{\"schema_version\":1,\"snapshots\":[]}'"
  exit "$EXIT_ITEM_MISSING"
fi

# Parse existing notes
EXISTING_NOTES="$(echo "$EXISTING_ITEM_JSON" | jq -r '.notes // ""')"
if [[ -z "$EXISTING_NOTES" ]]; then
  err "item exists but .notes is empty"
  exit "$EXIT_ITEM_MISSING"
fi

# Validate existing structure
if ! echo "$EXISTING_NOTES" | jq -e '.schema_version == 1 and .snapshots | type == "array"' >/dev/null 2>&1; then
  err "existing item .notes is not valid snapshot structure"
  err "Expected: {\"schema_version\":1,\"snapshots\":[...]}"
  exit "$EXIT_ITEM_MISSING"
fi

#--- append + trim history -----------------------------------------------------
info "appending snapshot to history (max: $SNAPSHOT_HISTORY_MAX)..."
NEW_NOTES="$(echo "$EXISTING_NOTES" | jq \
  --argjson new_entry "$SNAPSHOT_ENTRY" \
  --argjson max "$SNAPSHOT_HISTORY_MAX" \
  '.snapshots = ([$new_entry] + .snapshots) | .snapshots = .snapshots[0:$max]')"

#--- write back to BW ----------------------------------------------------------
info "writing updated snapshot to Bitwarden..."
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

# Build the full item JSON for `bw edit`
echo "$EXISTING_ITEM_JSON" | jq --arg notes "$NEW_NOTES" '.notes = $notes' > "$TMP_FILE"

if ! bw_sesh edit item "$EXISTING_ITEM_ID" < "$TMP_FILE" >/dev/null 2>&1; then
  err "bw edit item failed"
  exit "$EXIT_BW_WRITE_FAILED"
fi

#--- summary -------------------------------------------------------------------
SNAPSHOT_COUNT="$(echo "$NEW_NOTES" | jq '.snapshots | length')"
ok "snapshot complete"
echo
echo "  timestamp:  $TIMESTAMP_UTC"
echo "  backend:    ${BACKEND_URL:-<unknown>}"
echo "  repo SHA:   ${ASSISTANT_REPO_SHA:-<unknown>}"
echo "  state size: $STATE_BYTE_SIZE bytes"
echo "  history:    $SNAPSHOT_COUNT snapshot(s)"
echo
echo "To restore:"
echo "  scripts/restore-state.sh --list"
echo "  scripts/restore-state.sh                    # most recent"
echo "  scripts/restore-state.sh --index N          # specific entry"
