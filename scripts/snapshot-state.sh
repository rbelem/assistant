***REMOVED***!/usr/bin/env bash
***REMOVED*** snapshot-state.sh — defensive backup of tofu state to Bitwarden SM
***REMOVED***
***REMOVED*** Reads the current .tfstate from the live S3 backend, base64-encodes it,
***REMOVED*** and appends it to a history chain in TOFU_STATE_SNAPSHOT (Bitwarden SM
***REMOVED*** secret). Trims to SNAPSHOT_HISTORY_MAX entries (default 10) to keep
***REMOVED*** note size bounded. Captures backend URL + git SHA for cross-reference.
***REMOVED***
***REMOVED*** Uses bws (official Bitwarden Secrets Manager CLI) via scripts/lib/bws.sh.
***REMOVED*** No master password, no interactive login — only a BWS access token.
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   scripts/snapshot-state.sh              ***REMOVED*** snapshot current state
***REMOVED***   scripts/snapshot-state.sh --help       ***REMOVED*** this message
***REMOVED***
***REMOVED*** Environment:
***REMOVED***   BWS_ACCESS_TOKEN            SM machine-account access token
***REMOVED***   SNAPSHOT_BW_ITEM            SM secret key (default: TOFU_STATE_SNAPSHOT)
***REMOVED***   SNAPSHOT_HISTORY_MAX        max snapshots to keep (default: 10)
***REMOVED***   TOFU_DIR                    path to tofu/ directory (default: ../tofu relative to script)
***REMOVED***
***REMOVED*** Exit codes:
***REMOVED***   0  success
***REMOVED***   1  usage error
***REMOVED***   2  bws unavailable
***REMOVED***   3  item missing
***REMOVED***   4  tofu state pull failed
***REMOVED***   5  bws write failed

set -euo pipefail
source "$(dirname "$0")/lib/bws.sh"

***REMOVED***--- exit codes ----------------------------------------------------------------
readonly EXIT_USAGE=1
readonly EXIT_BW_UNAVAILABLE=2
readonly EXIT_ITEM_MISSING=3
readonly EXIT_TOFU_FAILED=4
readonly EXIT_BW_WRITE_FAILED=5

***REMOVED***--- config --------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_BW_ITEM="${SNAPSHOT_BW_ITEM:-TOFU_STATE_SNAPSHOT}"
SNAPSHOT_HISTORY_MAX="${SNAPSHOT_HISTORY_MAX:-10}"
TOFU_DIR="${TOFU_DIR:-$REPO_ROOT/tofu}"

***REMOVED***--- colors + helpers ----------------------------------------------------------
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

***REMOVED***--- arg parsing ---------------------------------------------------------------
while [[ $***REMOVED*** -gt 0 ]]; do
  case "$1" in
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^***REMOVED*** \?//'; exit 0 ;;
    *)          err "unknown arg: $1"; exit "$EXIT_USAGE" ;;
  esac
  ***REMOVED*** shellcheck disable=SC2317  ***REMOVED*** shift is reachable if case branches are added
  shift
done

***REMOVED***--- preflight -----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { err "missing required binary: $1"; exit "$EXIT_USAGE"; }
}
need jq
need base64

***REMOVED*** bws preflight: verify SM access token
bws_check || exit "$EXIT_BW_UNAVAILABLE"

***REMOVED*** Resolve project ID once for this run
BWS_PROJECT_ID="$(bws project list -o json 2>/dev/null | jq -r '.[] | select(.name == "assistant") | .id')"
if [[ -z "$BWS_PROJECT_ID" || "$BWS_PROJECT_ID" == "null" ]]; then
  err "bws: assistant project not found in SM"
  exit "$EXIT_BW_UNAVAILABLE"
fi

***REMOVED*** Resolve secret ID for TOFU_STATE_SNAPSHOT
SECRET_ID="$(bws secret list -o json "$BWS_PROJECT_ID" 2>/dev/null | jq -r --arg k "$SNAPSHOT_BW_ITEM" '.[] | select(.key == $k) | .id')"
if [[ -z "$SECRET_ID" || "$SECRET_ID" == "null" ]]; then
  err "SM secret '$SNAPSHOT_BW_ITEM' not found. Create it first with:"
  err "  scripts/populate-sm.sh  ***REMOVED*** or create via Bitwarden SM web vault"
  exit "$EXIT_ITEM_MISSING"
fi

***REMOVED***--- detect backend URL --------------------------------------------------------
***REMOVED*** Try .rendered/backend.conf first (materialized by tofu-wrapper.sh), then fall
***REMOVED*** back to parsing tofu state metadata if available.
BACKEND_URL=""
if [[ -f "$REPO_ROOT/.rendered/backend.conf" ]]; then
  ***REMOVED*** Extract endpoint + bucket from backend.conf
  endpoint="$(grep -E '^\s*endpoint\s*=' "$REPO_ROOT/.rendered/backend.conf" | sed 's/.*=\s*"\(.*\)"/\1/' || true)"
  bucket="$(grep -E '^\s*bucket\s*=' "$REPO_ROOT/.rendered/backend.conf" | sed 's/.*=\s*"\(.*\)"/\1/' || true)"
  if [[ -n "$endpoint" && -n "$bucket" ]]; then
    BACKEND_URL="s3://${bucket}@${endpoint}"
  fi
fi

***REMOVED***--- get git SHA ---------------------------------------------------------------
ASSISTANT_REPO_SHA=""
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  ASSISTANT_REPO_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
fi

***REMOVED***--- pull tofu state -----------------------------------------------------------
info "pulling tofu state from $TOFU_DIR..."
if [[ ! -d "$TOFU_DIR" ]]; then
  err "tofu directory not found: $TOFU_DIR"
  exit "$EXIT_TOFU_FAILED"
fi

***REMOVED*** tofu state pull requires the backend to be initialized. If .terraform doesn't
***REMOVED*** exist, we can't pull. (Operator should run `tofu init` first.)
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

***REMOVED*** Validate it's JSON
if ! echo "$STATE_JSON" | jq -e . >/dev/null 2>&1; then
  err "tofu state pull returned invalid JSON"
  exit "$EXIT_TOFU_FAILED"
fi

STATE_BYTE_SIZE="${***REMOVED***STATE_JSON}"
STATE_B64="$(echo "$STATE_JSON" | gzip -9 | base64 -w 0)"
TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

ok "pulled state: $STATE_BYTE_SIZE bytes"

***REMOVED***--- build snapshot entry ------------------------------------------------------
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

***REMOVED***--- read existing SM secret value --------------------------------------------
info "reading existing snapshot secret: $SNAPSHOT_BW_ITEM..."
EXISTING_NOTES=""
if ! EXISTING_NOTES="$(bws_get "$SNAPSHOT_BW_ITEM" 2>/dev/null)"; then
  err "SM secret '$SNAPSHOT_BW_ITEM' not found or not readable."
  exit "$EXIT_ITEM_MISSING"
fi

if [[ -z "$EXISTING_NOTES" ]]; then
  err "item exists but .notes is empty"
  exit "$EXIT_ITEM_MISSING"
fi

***REMOVED*** Validate existing structure
if ! echo "$EXISTING_NOTES" | jq -e '(.schema_version == 1) and ((.snapshots | type) == "array")' >/dev/null 2>&1; then
  err "existing item .notes is not valid snapshot structure"
  err "Expected: {\"schema_version\":1,\"snapshots\":[...]}"
  exit "$EXIT_ITEM_MISSING"
fi

***REMOVED***--- append + trim history -----------------------------------------------------
info "appending snapshot to history (max: $SNAPSHOT_HISTORY_MAX)..."
NEW_NOTES="$(echo "$EXISTING_NOTES" | jq \
  --argjson new_entry "$SNAPSHOT_ENTRY" \
  --argjson max "$SNAPSHOT_HISTORY_MAX" \
  '.snapshots = ([$new_entry] + .snapshots) | .snapshots = .snapshots[0:$max]')"

***REMOVED***--- write back to SM ----------------------------------------------------------
***REMOVED*** bws secret edit takes the value as a single argv (no --stdin/--value-file in bws 2.1.0).
***REMOVED*** Guard against E2BIG: Linux MAX_ARG_STRLEN is 128 KiB per argument.
if (( ${***REMOVED***NEW_NOTES} > 100000 )); then
  err "snapshot payload too large for bws argv: ${***REMOVED***NEW_NOTES} bytes (>100KiB)"
  err "reduce SNAPSHOT_HISTORY_MAX (currently $SNAPSHOT_HISTORY_MAX) or use a smaller state"
  exit "$EXIT_BW_WRITE_FAILED"
fi

info "writing updated snapshot to Secrets Manager..."
if ! bws secret edit "--value=$NEW_NOTES" "$SECRET_ID" 2>/dev/null; then
  err "bws secret edit failed"
  exit "$EXIT_BW_WRITE_FAILED"
fi

***REMOVED***--- summary -------------------------------------------------------------------
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
echo "  scripts/restore-state.sh                    ***REMOVED*** most recent"
echo "  scripts/restore-state.sh --index N          ***REMOVED*** specific entry"
echo
echo "=== First-run note ==="
echo "If this is the first snapshot, ensure the SM secret exists:"
echo "  bws secret create '$SNAPSHOT_BW_ITEM' '{\"schema_version\":1,\"snapshots\":[]}' \"\$BWS_PROJECT_ID\""
