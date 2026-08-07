***REMOVED***!/usr/bin/env bash
***REMOVED*** restore-state.sh — restore tofu state from Bitwarden SM snapshot
***REMOVED***
***REMOVED*** Reads from TOFU_STATE_SNAPSHOT (Bitwarden SM secret), decodes the
***REMOVED*** base64-encoded state, and writes it to a local file. Operator-driven:
***REMOVED*** never writes to a tofu backend automatically. Optional --push for backend
***REMOVED*** recovery (requires explicit confirmation).
***REMOVED***
***REMOVED*** Uses bws (official Bitwarden Secrets Manager CLI) via scripts/lib/bws.sh.
***REMOVED*** No master password, no interactive login — only a BWS access token.
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   scripts/restore-state.sh                    ***REMOVED*** restore most recent snapshot
***REMOVED***   scripts/restore-state.sh --list             ***REMOVED*** list available snapshots
***REMOVED***   scripts/restore-state.sh --index N          ***REMOVED*** restore specific entry (1=oldest)
***REMOVED***   scripts/restore-state.sh --output <path>    ***REMOVED*** custom output file
***REMOVED***   scripts/restore-state.sh --push             ***REMOVED*** also push to backend (requires confirm)
***REMOVED***   scripts/restore-state.sh --help             ***REMOVED*** this message
***REMOVED***
***REMOVED*** Environment:
***REMOVED***   BWS_ACCESS_TOKEN            SM machine-account access token
***REMOVED***   SNAPSHOT_BW_ITEM            SM secret key (default: TOFU_STATE_SNAPSHOT)
***REMOVED***   TOFU_DIR                    path to tofu/ directory (default: ../tofu relative to script)
***REMOVED***
***REMOVED*** Exit codes:
***REMOVED***   0  success
***REMOVED***   1  usage error
***REMOVED***   2  bws unavailable
***REMOVED***   3  item missing
***REMOVED***   4  no snapshots
***REMOVED***   5  write failed

set -euo pipefail
source "$(dirname "$0")/lib/bws.sh"

***REMOVED***--- exit codes ----------------------------------------------------------------
readonly EXIT_USAGE=1
readonly EXIT_BW_UNAVAILABLE=2
readonly EXIT_ITEM_MISSING=3
readonly EXIT_NO_SNAPSHOTS=4
readonly EXIT_WRITE_FAILED=5

***REMOVED***--- config --------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_BW_ITEM="${SNAPSHOT_BW_ITEM:-TOFU_STATE_SNAPSHOT}"
TOFU_DIR="${TOFU_DIR:-$REPO_ROOT/tofu}"
DEFAULT_OUTPUT="./terraform.tfstate.restored"

***REMOVED***--- args ----------------------------------------------------------------------
LIST_ONLY=0
SNAPSHOT_INDEX=""
OUTPUT_PATH="$DEFAULT_OUTPUT"
PUSH_TO_BACKEND=0

while [[ $***REMOVED*** -gt 0 ]]; do
  case "$1" in
    --list)       LIST_ONLY=1 ;;
    --index)      SNAPSHOT_INDEX="$2"; shift ;;
    --output)     OUTPUT_PATH="$2"; shift ;;
    --push)       PUSH_TO_BACKEND=1 ;;
    -h|--help)    sed -n '2,/^$/p' "$0" | sed 's/^***REMOVED*** \?//'; exit 0 ;;
    *)            echo "unknown arg: $1" >&2; exit "$EXIT_USAGE" ;;
  esac
  shift
done

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

***REMOVED***--- preflight -----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { err "missing required binary: $1"; exit "$EXIT_USAGE"; }
}
need jq
need base64

***REMOVED*** bws preflight: verify SM access token
bws_check || exit "$EXIT_BW_UNAVAILABLE"

***REMOVED***--- read SM secret ------------------------------------------------------------
info "reading snapshot secret: $SNAPSHOT_BW_ITEM..."
NOTES=""
if ! NOTES="$(bws_get "$SNAPSHOT_BW_ITEM" 2>/dev/null)"; then
  err "SM secret '$SNAPSHOT_BW_ITEM' not found."
  exit "$EXIT_ITEM_MISSING"
fi

if [[ -z "$NOTES" ]]; then
  err "item .notes is empty"
  exit "$EXIT_ITEM_MISSING"
fi

***REMOVED*** Validate structure
if ! echo "$NOTES" | jq -e '(.schema_version == 1) and ((.snapshots | type) == "array")' >/dev/null 2>&1; then
  err "item .notes is not valid snapshot structure"
  exit "$EXIT_ITEM_MISSING"
fi

SNAPSHOT_COUNT="$(echo "$NOTES" | jq '.snapshots | length')"
if [[ "$SNAPSHOT_COUNT" -eq 0 ]]; then
  err "no snapshots in item"
  exit "$EXIT_NO_SNAPSHOTS"
fi

***REMOVED***--- list mode -----------------------------------------------------------------
if [[ "$LIST_ONLY" -eq 1 ]]; then
  echo
  echo "Available snapshots ($SNAPSHOT_COUNT total):"
  echo
  echo "$NOTES" | jq -r '
    .snapshots | to_entries | reverse | .[] |
    "  [\(.key + 1)] \(.value.timestamp_utc)  \(.value.byte_size) bytes  \(.value.backend // "<unknown backend>")"
  '
  echo
  echo "Most recent: [1]  Oldest: [$SNAPSHOT_COUNT]"
  echo
  echo "To restore:"
  echo "  scripts/restore-state.sh                    ***REMOVED*** most recent"
  echo "  scripts/restore-state.sh --index N          ***REMOVED*** specific entry"
  exit 0
fi

***REMOVED***--- resolve snapshot index ----------------------------------------------------
***REMOVED*** snapshots[] is stored newest-first (snapshot-state.sh prepends). So index 1 = newest.
if [[ -z "$SNAPSHOT_INDEX" ]]; then
  SNAPSHOT_INDEX=1
fi

if ! [[ "$SNAPSHOT_INDEX" =~ ^[0-9]+$ ]] || [[ "$SNAPSHOT_INDEX" -lt 1 ]] || [[ "$SNAPSHOT_INDEX" -gt "$SNAPSHOT_COUNT" ]]; then
  err "invalid --index: $SNAPSHOT_INDEX (must be 1..$SNAPSHOT_COUNT)"
  exit "$EXIT_USAGE"
fi

***REMOVED*** Convert 1-based index to 0-based array index (newest-first, so index 1 = array[0])
ARRAY_INDEX=$((SNAPSHOT_INDEX - 1))

SNAPSHOT_ENTRY="$(echo "$NOTES" | jq --argjson idx "$ARRAY_INDEX" '.snapshots[$idx]')"
TIMESTAMP_UTC="$(echo "$SNAPSHOT_ENTRY" | jq -r '.timestamp_utc')"
BYTE_SIZE="$(echo "$SNAPSHOT_ENTRY" | jq -r '.byte_size')"
BACKEND="$(echo "$SNAPSHOT_ENTRY" | jq -r '.backend // "<unknown>"')"
STATE_B64="$(echo "$SNAPSHOT_ENTRY" | jq -r '.state_b64')"

***REMOVED***--- warning banner ------------------------------------------------------------
echo
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}  THIS IS A RESTORE OPERATION${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo
echo "  snapshot:   [$SNAPSHOT_INDEX] of $SNAPSHOT_COUNT"
echo "  timestamp:  $TIMESTAMP_UTC"
echo "  backend:    $BACKEND"
echo "  size:       $BYTE_SIZE bytes"
echo "  output:     $OUTPUT_PATH"
echo
if [[ "$PUSH_TO_BACKEND" -eq 1 ]]; then
  echo -e "${YELLOW}  --push is set: after writing the file, this will run:${NC}"
  echo -e "${YELLOW}    tofu -chdir=$TOFU_DIR state push $OUTPUT_PATH${NC}"
  echo
fi

***REMOVED***--- decode + write ------------------------------------------------------------
info "decoding base64 state..."
STATE_JSON="$(echo "$STATE_B64" | base64 -d | gunzip)"

***REMOVED*** Validate decoded JSON
if ! echo "$STATE_JSON" | jq -e . >/dev/null 2>&1; then
  err "decoded state is not valid JSON"
  exit "$EXIT_WRITE_FAILED"
fi

info "writing to $OUTPUT_PATH..."
if ! echo "$STATE_JSON" > "$OUTPUT_PATH"; then
  err "failed to write: $OUTPUT_PATH"
  exit "$EXIT_WRITE_FAILED"
fi

***REMOVED*** Compute SHA256 for verification
SHA256="$(sha256sum "$OUTPUT_PATH" | awk '{print $1}')"
ACTUAL_SIZE="$(wc -c < "$OUTPUT_PATH")"

ok "wrote $OUTPUT_PATH"
echo
echo "  SHA256:     $SHA256"
echo "  size:       $ACTUAL_SIZE bytes"
echo

***REMOVED***--- optional push to backend --------------------------------------------------
if [[ "$PUSH_TO_BACKEND" -eq 1 ]]; then
  warn "about to push state to backend: $BACKEND"
  warn "this will OVERWRITE the current remote state"
  echo
  read -r -p "Type 'yes' to confirm: " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    err "push cancelled"
    exit 0
  fi

  info "pushing state to backend..."
  if [[ ! -d "$TOFU_DIR" ]]; then
    err "tofu directory not found: $TOFU_DIR"
    exit "$EXIT_WRITE_FAILED"
  fi

  if ! tofu -chdir="$TOFU_DIR" state push "$OUTPUT_PATH" 2>&1; then
    err "tofu state push failed"
    exit "$EXIT_WRITE_FAILED"
  fi

  ok "state pushed to backend"
fi

***REMOVED***--- summary -------------------------------------------------------------------
echo
echo "restore complete."
echo
echo "Next steps:"
echo "  1. Verify the restored state:"
echo "     tofu -chdir=$TOFU_DIR state list"
echo "  2. If satisfied, replace the backend state:"
echo "     scripts/restore-state.sh --push"
echo "  3. Or manually:"
echo "     tofu -chdir=$TOFU_DIR state push $OUTPUT_PATH"
