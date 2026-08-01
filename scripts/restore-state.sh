#!/usr/bin/env bash
# restore-state.sh — restore tofu state from Bitwarden snapshot
#
# Reads from assistant/tofu-state-snapshot (BW Secure Note), decodes the
# base64-encoded state, and writes it to a local file. Operator-driven:
# never writes to a tofu backend automatically. Optional --push for backend
# recovery (requires explicit confirmation).
#
# Uses the `bitw` CLI (rbelem fork). bitw auto-unlocks via libsecret keyring
# (entry "bitwarden master-password"), or the PASSWORD env var, or an
# interactive prompt. No session tokens, no BW_SESSION.
#
# Usage:
#   scripts/restore-state.sh                    # restore most recent snapshot
#   scripts/restore-state.sh --list             # list available snapshots
#   scripts/restore-state.sh --index N          # restore specific entry (1=oldest)
#   scripts/restore-state.sh --output <path>    # custom output file
#   scripts/restore-state.sh --push             # also push to backend (requires confirm)
#   scripts/restore-state.sh --help             # this message
#
# Environment:
#   PASSWORD                optional (bitw reads it for master password from
#                           libsecret keyring; this env var overrides if set)
#   SNAPSHOT_BW_ITEM        BW item name (default: assistant/tofu-state-snapshot)
#   TOFU_DIR                path to tofu/ directory (default: ../tofu relative to script)
#
# Exit codes:
#   0  success
#   1  usage error
#   2  BW unavailable
#   3  item missing
#   4  no snapshots
#   5  write failed

set -euo pipefail

#--- exit codes ----------------------------------------------------------------
readonly EXIT_USAGE=1
readonly EXIT_BW_UNAVAILABLE=2
readonly EXIT_ITEM_MISSING=3
readonly EXIT_NO_SNAPSHOTS=4
readonly EXIT_WRITE_FAILED=5

#--- config --------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_BW_ITEM="${SNAPSHOT_BW_ITEM:-assistant/tofu-state-snapshot}"
TOFU_DIR="${TOFU_DIR:-$REPO_ROOT/tofu}"
DEFAULT_OUTPUT="./terraform.tfstate.restored"

#--- args ----------------------------------------------------------------------
LIST_ONLY=0
SNAPSHOT_INDEX=""
OUTPUT_PATH="$DEFAULT_OUTPUT"
PUSH_TO_BACKEND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)       LIST_ONLY=1 ;;
    --index)      SNAPSHOT_INDEX="$2"; shift ;;
    --output)     OUTPUT_PATH="$2"; shift ;;
    --push)       PUSH_TO_BACKEND=1 ;;
    -h|--help)    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)            echo "unknown arg: $1" >&2; exit "$EXIT_USAGE" ;;
  esac
  shift
done

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

#--- preflight -----------------------------------------------------------------
need() {
  command -v "$1" >/dev/null 2>&1 \
    || { err "missing required binary: $1"; exit "$EXIT_USAGE"; }
}
need bitw
need jq
need python3
need base64

# bitw preflight: verify login tokens exist
if ! bitw status 2>/dev/null | grep -q 'token_valid.*valid'; then
  err "bitw login tokens not found."
  err "Run: bitw login"
  err "Or store master password: secret-tool store --label=\"Bitwarden\" bitwarden master-password"
  exit "$EXIT_BW_UNAVAILABLE"
fi

# Sync vault cache
bitw sync 2>/dev/null || true

#--- read BW item --------------------------------------------------------------
info "reading snapshot item: $SNAPSHOT_BW_ITEM..."
NOTES=""
if ! NOTES="$(bitw get --field notes "$SNAPSHOT_BW_ITEM" 2>/dev/null)"; then
  err "item not found: $SNAPSHOT_BW_ITEM"
  err "Create it first with snapshot-state.sh or manually:"
  err "  bitw create '$SNAPSHOT_BW_ITEM' --type 2 --notes '{\"schema_version\":1,\"snapshots\":[]}'"
  exit "$EXIT_ITEM_MISSING"
fi

if [[ -z "$NOTES" ]]; then
  err "item .notes is empty"
  exit "$EXIT_ITEM_MISSING"
fi

# Validate structure
if ! echo "$NOTES" | jq -e '.schema_version == 1 and .snapshots | type == "array"' >/dev/null 2>&1; then
  err "item .notes is not valid snapshot structure"
  exit "$EXIT_ITEM_MISSING"
fi

SNAPSHOT_COUNT="$(echo "$NOTES" | jq '.snapshots | length')"
if [[ "$SNAPSHOT_COUNT" -eq 0 ]]; then
  err "no snapshots in item"
  exit "$EXIT_NO_SNAPSHOTS"
fi

#--- list mode -----------------------------------------------------------------
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
  echo "  scripts/restore-state.sh                    # most recent"
  echo "  scripts/restore-state.sh --index N          # specific entry"
  exit 0
fi

#--- resolve snapshot index ----------------------------------------------------
# snapshots[] is stored newest-first (snapshot-state.sh prepends). So index 1 = newest.
if [[ -z "$SNAPSHOT_INDEX" ]]; then
  SNAPSHOT_INDEX=1
fi

if ! [[ "$SNAPSHOT_INDEX" =~ ^[0-9]+$ ]] || [[ "$SNAPSHOT_INDEX" -lt 1 ]] || [[ "$SNAPSHOT_INDEX" -gt "$SNAPSHOT_COUNT" ]]; then
  err "invalid --index: $SNAPSHOT_INDEX (must be 1..$SNAPSHOT_COUNT)"
  exit "$EXIT_USAGE"
fi

# Convert 1-based index to 0-based array index (newest-first, so index 1 = array[0])
ARRAY_INDEX=$((SNAPSHOT_INDEX - 1))

SNAPSHOT_ENTRY="$(echo "$NOTES" | jq --argjson idx "$ARRAY_INDEX" '.snapshots[$idx]')"
TIMESTAMP_UTC="$(echo "$SNAPSHOT_ENTRY" | jq -r '.timestamp_utc')"
BYTE_SIZE="$(echo "$SNAPSHOT_ENTRY" | jq -r '.byte_size')"
BACKEND="$(echo "$SNAPSHOT_ENTRY" | jq -r '.backend // "<unknown>"')"
STATE_B64="$(echo "$SNAPSHOT_ENTRY" | jq -r '.state_b64')"

#--- warning banner ------------------------------------------------------------
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

#--- decode + write ------------------------------------------------------------
info "decoding base64 state..."
STATE_JSON="$(echo "$STATE_B64" | base64 -d)"

# Validate decoded JSON
if ! echo "$STATE_JSON" | jq -e . >/dev/null 2>&1; then
  err "decoded state is not valid JSON"
  exit "$EXIT_WRITE_FAILED"
fi

info "writing to $OUTPUT_PATH..."
if ! echo "$STATE_JSON" > "$OUTPUT_PATH"; then
  err "failed to write: $OUTPUT_PATH"
  exit "$EXIT_WRITE_FAILED"
fi

# Compute SHA256 for verification
SHA256="$(sha256sum "$OUTPUT_PATH" | awk '{print $1}')"
ACTUAL_SIZE="$(wc -c < "$OUTPUT_PATH")"

ok "wrote $OUTPUT_PATH"
echo
echo "  SHA256:     $SHA256"
echo "  size:       $ACTUAL_SIZE bytes"
echo

#--- optional push to backend --------------------------------------------------
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

#--- summary -------------------------------------------------------------------
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
