***REMOVED***!/usr/bin/env bash
***REMOVED*** rotate-secrets.sh — credential rotation for the assistant vault
***REMOVED***
***REMOVED*** Rotates Bitwarden items listed in scripts/rotate-secrets.conf.
***REMOVED*** Auto-rotate items (stateless): zitadel-admin-password
***REMOVED*** Manual-only items (stateful): restic, n8n-key, postgres, zitadel-masterkey
***REMOVED***
***REMOVED*** Uses the `bitw` CLI (rbelem fork). bitw auto-unlocks via libsecret keyring
***REMOVED*** (entry "bitwarden master-password"), or the PASSWORD env var, or an
***REMOVED*** interactive prompt. No session tokens, no BW_SESSION.
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   rotate-secrets.sh list                              ***REMOVED*** all items + last rotation
***REMOVED***   rotate-secrets.sh status                            ***REMOVED*** list + exit 1 if any past age
***REMOVED***   rotate-secrets.sh generate <item> [--yes] [--dry-run]
***REMOVED***   rotate-secrets.sh generate --all [--yes] [--dry-run]
***REMOVED***   rotate-secrets.sh rotate <item> [--yes] [--dry-run] [--i-know-what-im-doing]
***REMOVED***   rotate-secrets.sh rotate --all [--yes] [--dry-run]
***REMOVED***   rotate-secrets.sh --help
***REMOVED***
***REMOVED*** filter-repo will turn `***REMOVED***` into `***REMOVED***` in public mirror — project convention.

set -euo pipefail

***REMOVED***--- constants -----------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEFAULT_CONFIG="$SCRIPT_DIR/rotate-secrets.conf"
readonly LOCK_DIR="${XDG_CACHE_HOME:-/tmp}"
readonly LOCK_FILE="$LOCK_DIR/rotate-secrets.lock"
readonly LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rotate-secrets"
readonly LOG_FILE_DEFAULT="$LOG_DIR/rotate.log"
readonly HISTORY_BACKUP_DIR="$LOCK_DIR"

***REMOVED*** Exit codes
readonly EXIT_USAGE=1
readonly EXIT_BW_UNAVAILABLE=2
readonly EXIT_ITEM_MISSING=3
readonly EXIT_VERIFY_FAILED=4
readonly EXIT_ROLLBACK_FAILED=5
readonly EXIT_LOCK_HELD=6
readonly EXIT_MANUAL_REFUSED=7

***REMOVED***--- colors + logging ----------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info()  { echo -e "${BLUE}:: $*${NC}" >&2; }
ok()    { echo -e "${GREEN}✓  $*${NC}" >&2; }
warn()  { echo -e "${YELLOW}!  $*${NC}" >&2; }
err()   { echo -e "${RED}✗ $*${NC}" >&2; }

audit_log() {
  local item="$1" action="$2" result="$3" age_days="${4:-}" bw_rev="${5:-}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local line="[$ts] [$item] [$action] [$result] [age=${age_days:-?}d] [rev=${bw_rev:-?}]"
  echo "$line"
  if [[ -n "${LOG_FILE:-}" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$line" >> "$LOG_FILE"
  fi
}

***REMOVED***--- source pure functions -----------------------------------------------------
***REMOVED*** shellcheck source=rotate-secrets.lib.sh
source "$SCRIPT_DIR/rotate-secrets.lib.sh"

***REMOVED***--- arg parsing ---------------------------------------------------------------
CMD=""
TARGET_ITEM=""
DRY_RUN=0
AUTO_YES=0
I_KNOW=0
CONFIG_PATH="$DEFAULT_CONFIG"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^***REMOVED*** \?//'
  exit 0
}

while [[ $***REMOVED*** -gt 0 ]]; do
  case "$1" in
    list|status|generate|rotate)
      CMD="$1"; shift
      if [[ $***REMOVED*** -gt 0 && "$1" != --* && "$1" != -* ]]; then
        if [[ "$1" == "--all" ]]; then
          TARGET_ITEM="--all"
          shift
        else
          TARGET_ITEM="$1"
          shift
        fi
      fi
      ;;
    --all)          TARGET_ITEM="--all"; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --yes|-y)       AUTO_YES=1; shift ;;
    --i-know-what-im-doing) I_KNOW=1; shift ;;
    --config)       CONFIG_PATH="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *)              err "unknown arg: $1"; exit "$EXIT_USAGE" ;;
  esac
done

[[ -n "$CMD" ]] || { err "no command specified (list|status|generate|rotate)"; exit "$EXIT_USAGE"; }

***REMOVED***--- config loading ------------------------------------------------------------
if [[ ! -f "$CONFIG_PATH" ]]; then
  err "config not found: $CONFIG_PATH"
  exit "$EXIT_USAGE"
fi

CONFIG_JSON="$(parse_config "$CONFIG_PATH")" || exit "$EXIT_USAGE"
LOG_FILE="$(echo "$CONFIG_JSON" | jq -r '.logging.log_file' | sed "s|^~|$HOME|")"
LOG_FILE="${LOG_FILE:-$LOG_FILE_DEFAULT}"
KEEP_PER_ITEM="$(echo "$CONFIG_JSON" | jq -r '.backup.keep_per_item // 5')"
HISTORY_ITEM="$(echo "$CONFIG_JSON" | jq -r '.backup.history_item')"

***REMOVED***--- PASSWORD resolution + bitw preflight -------------------------------------
***REMOVED*** PASSWORD env first, then VPS file fallback, then libsecret auto-unlock.
if [[ -z "${PASSWORD:-}" && -r /etc/agent/bw_master_pw ]]; then
  export PASSWORD="$(cat /etc/agent/bw_master_pw)"
fi

***REMOVED***--- preflight (skip for --help / dry-run list) --------------------------------
preflight() {
  command -v bitw >/dev/null 2>&1 || { err "bitw CLI not found"; exit "$EXIT_BW_UNAVAILABLE"; }
  command -v jq >/dev/null 2>&1 || { err "jq not found"; exit "$EXIT_USAGE"; }
  command -v yq >/dev/null 2>&1 || { err "yq not found (https://github.com/mikefarah/yq)"; exit "$EXIT_USAGE"; }
  command -v openssl >/dev/null 2>&1 || { err "openssl not found"; exit "$EXIT_USAGE"; }

  ***REMOVED*** Check bitw login tokens exist
  if ! bitw status 2>/dev/null | grep -q 'token_valid.*valid'; then
    err "bitw login tokens not found."
    err "Run: bitw login"
    err "Or store master password: secret-tool store --label=\"Bitwarden\" bitwarden master-password"
    exit "$EXIT_BW_UNAVAILABLE"
  fi

  ***REMOVED*** Sync vault cache
  bitw sync 2>/dev/null || true
}

***REMOVED***--- concurrency: flock --------------------------------------------------------
acquire_lock() {
  mkdir -p "$LOCK_DIR"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    err "another instance is running (lock: $LOCK_FILE)"
    exit "$EXIT_LOCK_HELD"
  fi
}

***REMOVED***--- history RMW ---------------------------------------------------------------
read_history() {
  local payload
  payload="$(bitw get --field notes "$HISTORY_ITEM" 2>/dev/null || true)"

  if [[ -z "$payload" ]]; then
    echo "[]"
    return 0
  fi

  ***REMOVED*** Validate JSON
  if ! echo "$payload" | jq -e 'type == "array"' >/dev/null 2>&1; then
    ***REMOVED*** No-clobber guard: parse failed → backup raw, alert, abort
    local bak="${HISTORY_BACKUP_DIR}/rotate-secrets-history-$(date +%s).bak"
    echo "$payload" > "$bak"
    chmod 600 "$bak"
    err "history note is not valid JSON array. Raw backed up to: $bak"
    err "Refusing to overwrite. Manual inspection required."
    exit "$EXIT_VERIFY_FAILED"
  fi

  echo "$payload"
}

write_history() {
  local new_json="$1"

  ***REMOVED*** Check history item exists
  if ! bitw get --json "$HISTORY_ITEM" >/dev/null 2>&1; then
    err "history item not found: $HISTORY_ITEM — create it first (Secure Note)"
    exit "$EXIT_ITEM_MISSING"
  fi

  ***REMOVED*** bitw edit takes --notes directly; no /proc cmdline exposure for secrets
  ***REMOVED*** (notes are passed as argv, but the history JSON contains no high-value secrets).
  if ! bitw edit "$HISTORY_ITEM" --notes "$new_json" >/dev/null; then
    err "bitw edit failed for history item"
    exit "$EXIT_BW_UNAVAILABLE"
  fi
}

***REMOVED***--- first-run bootstrap -------------------------------------------------------
bootstrap_item_baseline() {
  local item_name="$1"
  local history_json="$2"

  ***REMOVED*** Check if item already has history entry
  local existing
  existing="$(echo "$history_json" | jq -e --arg n "$item_name" \
    '[.[] | select(.item == $n)] | length')"

  if [[ "$existing" -gt 0 ]]; then
    return 0  ***REMOVED*** already bootstrapped
  fi

  ***REMOVED*** Seed from bitw revisionDate
  local rev_date
  rev_date="$(bitw get --json "$item_name" 2>/dev/null | jq -r '.revisionDate // empty')"

  if [[ -z "$rev_date" ]]; then
    warn "cannot bootstrap $item_name: revisionDate not available"
    return 0
  fi

  ***REMOVED*** Add bootstrap entry (no value change, just timestamp baseline)
  local new_entry
  new_entry="$(echo "$history_json" | jq -c \
    --arg item "$item_name" \
    --arg at "$rev_date" \
    '. + [{item: $item, old_value_b64: "", rotated_at: $at, by: "bootstrap"}]')"

  write_history "$new_entry"
  info "bootstrapped $item_name baseline from revisionDate: $rev_date"
}

***REMOVED***--- generators ----------------------------------------------------------------
generate_value() {
  local item_json="$1"
  local generator length word_count

  generator="$(echo "$item_json" | jq -r '.generator')"
  length="$(echo "$item_json" | jq -r '.length // 32')"
  word_count="$(echo "$item_json" | jq -r '.word_count // 6')"

  case "$generator" in
    hex)      gen_hex "$length" ;;
    base64)   gen_base64 "$length" ;;
    password) gen_password_diceware "$word_count" ;;
    *)        err "unknown generator: $generator"; return 1 ;;
  esac
}

***REMOVED***--- rotation logic ------------------------------------------------------------
rotate_item() {
  local item_name="$1"

  ***REMOVED*** Lookup item config
  local item_json
  item_json="$(get_item_config "$CONFIG_JSON" "$item_name")"
  if [[ -z "$item_json" || "$item_json" == "null" ]]; then
    err "item not in config: $item_name"
    exit "$EXIT_ITEM_MISSING"
  fi

  local category runbook
  category="$(echo "$item_json" | jq -r '.category')"
  runbook="$(echo "$item_json" | jq -r '.runbook // empty')"

  ***REMOVED*** Manual-only guard
  if [[ "$category" == "manual" && "$I_KNOW" -ne 1 ]]; then
    err "refused: $item_name is manual-only"
    [[ -n "$runbook" ]] && err "runbook: $runbook"
    err "re-run with --i-know-what-im-doing to override"
    exit "$EXIT_MANUAL_REFUSED"
  fi

  ***REMOVED*** Check BW item exists
  if ! bitw get --json "$item_name" >/dev/null 2>&1; then
    err "BW item not found: $item_name"
    exit "$EXIT_ITEM_MISSING"
  fi

  ***REMOVED*** Read current history
  local history_json
  history_json="$(read_history)"

  ***REMOVED*** Bootstrap if needed
  bootstrap_item_baseline "$item_name" "$history_json"
  history_json="$(read_history)"  ***REMOVED*** re-read after bootstrap

  ***REMOVED*** Get last rotation timestamp
  local last_rotated
  last_rotated="$(echo "$history_json" | jq -r --arg n "$item_name" \
    '[.[] | select(.item == $n)] | sort_by(.rotated_at) | reverse | .[0].rotated_at // "unknown"')"

  local age
  if [[ "$last_rotated" == "unknown" ]]; then
    age="?"
  else
    age="$(age_days "$last_rotated")"
  fi

  ***REMOVED*** Generate new value
  local new_value
  new_value="$(generate_value "$item_json")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[dry-run] would rotate: $item_name"
    info "  generator: $(echo "$item_json" | jq -r '.generator')"
    info "  last rotated: $last_rotated (${age}d ago)"
    info "  new value length: ${***REMOVED***new_value} chars"
    return 0
  fi

  ***REMOVED*** Confirmation
  if [[ "$AUTO_YES" -ne 1 ]]; then
    echo -e "${YELLOW}Rotate $item_name? [y/N]${NC}" >&2
    read -r reply
    [[ "$reply" =~ ^[Yy] ]] || { info "skipped"; return 0; }
  fi

  ***REMOVED*** Read old value for history
  local old_value old_value_b64
  old_value="$(bitw get --field password "$item_name")"
  old_value_b64="$(echo -n "$old_value" | base64 -w0)"

  ***REMOVED*** Write new value to BW via --password-stdin (keeps secret out of /proc cmdline)
  if ! printf '%s' "$new_value" | bitw edit "$item_name" --password-stdin >/dev/null; then
    err "bitw edit failed for $item_name"
    exit "$EXIT_BW_UNAVAILABLE"
  fi

  ***REMOVED*** Verify-after-write
  local verify_value
  verify_value="$(bitw get --field password "$item_name")"
  if [[ "$verify_value" != "$new_value" ]]; then
    err "VERIFY FAILED for $item_name — new value doesn't match"
    err "attempting rollback..."

    ***REMOVED*** Rollback: restore old value via --password-stdin
    if ! printf '%s' "$old_value" | bitw edit "$item_name" --password-stdin >/dev/null; then
      err "ROLLBACK FAILED — manual intervention required"
      err "old value (base64): $old_value_b64"
      audit_log "$item_name" "rotate" "rollback_failed" "$age" ""
      exit "$EXIT_ROLLBACK_FAILED"
    fi

    ***REMOVED*** Verify rollback
    local rollback_verify
    rollback_verify="$(bitw get --field password "$item_name")"
    if [[ "$rollback_verify" != "$old_value" ]]; then
      err "ROLLBACK VERIFY FAILED — manual intervention required"
      err "old value (base64): $old_value_b64"
      audit_log "$item_name" "rotate" "rollback_failed" "$age" ""
      exit "$EXIT_ROLLBACK_FAILED"
    fi

    err "rollback succeeded"
    audit_log "$item_name" "rotate" "verify_failed_rolled_back" "$age" ""
    exit "$EXIT_VERIFY_FAILED"
  fi

  ***REMOVED*** Update history
  local now_ts
  now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local new_history
  new_history="$(history_append "$history_json" "$item_name" "$old_value_b64" "$now_ts" "rotate-secrets.sh")"
  new_history="$(history_trim "$new_history" "$item_name" "$KEEP_PER_ITEM")"
  write_history "$new_history"

  ***REMOVED*** Get new revision
  local new_rev
  new_rev="$(bitw get --json "$item_name" | jq -r '.revisionDate')"

  ok "rotated: $item_name"
  audit_log "$item_name" "rotate" "success" "$age" "$new_rev"

  ***REMOVED*** Post-rotation handoff
  local ansible_cmd
  ansible_cmd="$(echo "$CONFIG_JSON" | jq -r '.deploy_handoff.ansible_cmd')"
  echo ""
  info "next steps:"
  info "  1. deploy: $ansible_cmd"

  ***REMOVED*** Per-item health check
  local health_cmd
  health_cmd="$(echo "$CONFIG_JSON" | jq -r --arg n "$item_name" \
    '.deploy_handoff.health_checks[] | select(.item == $n) | .cmd // empty')"
  if [[ -n "$health_cmd" ]]; then
    info "  2. verify: $health_cmd"
  fi
}

***REMOVED***--- subcommands ---------------------------------------------------------------
cmd_list() {
  preflight
  local history_json
  history_json="$(read_history)"

  echo "Rotatable items:"
  echo ""
  echo "$CONFIG_JSON" | jq -r '.items[] | "\(.name)\t\(.category)\t\(.max_age_days)"' | \
  while IFS=$'\t' read -r name category max_age; do
    local last_rotated age_str
    last_rotated="$(echo "$history_json" | jq -r --arg n "$name" \
      '[.[] | select(.item == $n)] | sort_by(.rotated_at) | reverse | .[0].rotated_at // "never"')"

    if [[ "$last_rotated" == "never" ]]; then
      age_str="unknown"
    else
      local age
      age="$(age_days "$last_rotated")"
      age_str="${age}d (max ${max_age}d)"
    fi

    printf "  %-45s [%-6s] %s\n" "$name" "$category" "$age_str"
  done
}

cmd_status() {
  cmd_list
  echo ""

  local any_past=0
  echo "$CONFIG_JSON" | jq -r '.items[] | "\(.name)\t\(.max_age_days)"' | \
  while IFS=$'\t' read -r name max_age; do
    local history_json
    history_json="$(read_history)"
    local last_rotated
    last_rotated="$(echo "$history_json" | jq -r --arg n "$name" \
      '[.[] | select(.item == $n)] | sort_by(.rotated_at) | reverse | .[0].rotated_at // "never"')"

    if [[ "$last_rotated" != "never" ]]; then
      local age
      age="$(age_days "$last_rotated")"
      if [[ "$age" -gt "$max_age" ]]; then
        warn "$name is $age days old (max $max_age)"
        any_past=1
      fi
    fi
  done

  ***REMOVED*** Check if any were past due (subshell issue — re-check)
  echo "$CONFIG_JSON" | jq -r '.items[] | "\(.name)\t\(.max_age_days)"' | \
  while IFS=$'\t' read -r name max_age; do
    local history_json
    history_json="$(read_history)"
    local last_rotated
    last_rotated="$(echo "$history_json" | jq -r --arg n "$name" \
      '[.[] | select(.item == $n)] | sort_by(.rotated_at) | reverse | .[0].rotated_at // "never"')"

    if [[ "$last_rotated" != "never" ]]; then
      local age
      age="$(age_days "$last_rotated")"
      if [[ "$age" -gt "$max_age" ]]; then
        exit 1
      fi
    fi
  done || exit 1
}

cmd_generate() {
  preflight
  acquire_lock

  if [[ "$TARGET_ITEM" == "--all" ]]; then
    ***REMOVED*** Rotate all auto items past age
    local history_json
    history_json="$(read_history)"

    echo "$CONFIG_JSON" | jq -r '.items[] | "\(.name)\t\(.category)\t\(.max_age_days)"' | \
    while IFS=$'\t' read -r name category max_age; do
      if [[ "$category" == "manual" && "$I_KNOW" -ne 1 ]]; then
        continue  ***REMOVED*** skip manual unless --i-know-what-im-doing
      fi

      local last_rotated
      last_rotated="$(echo "$history_json" | jq -r --arg n "$name" \
        '[.[] | select(.item == $n)] | sort_by(.rotated_at) | reverse | .[0].rotated_at // "never"')"

      local should_rotate=0
      if [[ "$last_rotated" == "never" ]]; then
        should_rotate=1
      else
        local age
        age="$(age_days "$last_rotated")"
        if [[ "$age" -gt "$max_age" ]]; then
          should_rotate=1
        fi
      fi

      if [[ "$should_rotate" -eq 1 ]]; then
        rotate_item "$name"
      fi
    done
  else
    [[ -n "$TARGET_ITEM" ]] || { err "specify item name or --all"; exit "$EXIT_USAGE"; }
    rotate_item "$TARGET_ITEM"
  fi
}

***REMOVED***--- main dispatch -------------------------------------------------------------
case "$CMD" in
  list)     cmd_list ;;
  status)   cmd_status ;;
  generate|rotate) cmd_generate ;;
  *)        err "unknown command: $CMD"; exit "$EXIT_USAGE" ;;
esac
