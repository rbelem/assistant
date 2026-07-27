#!/usr/bin/env bash
# rotate-secrets.lib.sh — pure functions for rotate-secrets.sh
# Sourced by rotate-secrets.sh and tests/rotate-secrets.bats
# No side effects, no BW calls, no file I/O except explicit params

# age_days ISO_TIMESTAMP
# Returns age in days from ISO timestamp to now. Negative = future.
age_days() {
  local iso_ts="$1"
  local ts_epoch now_epoch
  ts_epoch="$(date -d "$iso_ts" +%s 2>/dev/null)" || return 1
  now_epoch="$(date +%s)"
  echo $(( (now_epoch - ts_epoch) / 86400 ))
}

# gen_hex BYTES
# Returns 2*BYTES hex chars (openssl rand -hex)
gen_hex() {
  local bytes="$1"
  openssl rand -hex "$bytes"
}

# gen_base64 BYTES
# Returns base64 without padding/newlines
gen_base64() {
  local bytes="$1"
  openssl rand -base64 "$bytes" | tr -d '\n='
}

# gen_password_diceware WORD_COUNT
# Returns WORD_COUNT space-separated words from Diceware list
# Uses /usr/share/dict/words if available, else fails
gen_password_diceware() {
  local word_count="$1"
  local wordlist="/usr/share/dict/words"
  
  [[ -f "$wordlist" ]] || {
    echo "ERROR: Diceware wordlist not found at $wordlist" >&2
    return 1
  }
  
  local total_words
  total_words="$(wc -l < "$wordlist")"
  
  local words=()
  local i
  for ((i=0; i<word_count; i++)); do
    # Use /dev/urandom for unbiased selection
    local idx
    idx="$(od -An -tu4 -N4 < /dev/urandom | tr -d ' ')"
    idx=$(( idx % total_words + 1 ))
    local word
    word="$(sed -n "${idx}p" "$wordlist")"
    words+=("$word")
  done
  
  echo "${words[*]}"
}

# history_append JSON_ARRAY ITEM OLD_VALUE_B64 ROTATED_AT BY
# Appends entry to JSON array, returns new array
history_append() {
  local json_array="$1"
  local item="$2"
  local old_value_b64="$3"
  local rotated_at="$4"
  local by="$5"
  
  # Validate input is valid JSON array
  if ! echo "$json_array" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: invalid JSON array" >&2
    return 1
  fi
  
  # Append new entry
  echo "$json_array" | jq -c \
    --arg item "$item" \
    --arg old "$old_value_b64" \
    --arg at "$rotated_at" \
    --arg by "$by" \
    '. + [{item: $item, old_value_b64: $old, rotated_at: $at, by: $by}]'
}

# history_trim JSON_ARRAY ITEM KEEP_COUNT
# Trims history for ITEM to KEEP_COUNT most recent entries (FIFO)
history_trim() {
  local json_array="$1"
  local item="$2"
  local keep_count="$3"
  
  # Validate input
  if ! echo "$json_array" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: invalid JSON array" >&2
    return 1
  fi
  
  # Split into matching and non-matching, trim matching, recombine
  echo "$json_array" | jq -c \
    --arg item "$item" \
    --argjson keep "$keep_count" \
    '
      [.[] | select(.item == $item)] as $matching |
      [.[] | select(.item != $item)] as $others |
      ($matching | sort_by(.rotated_at) | reverse | .[:$keep]) as $trimmed |
      $others + $trimmed
    '
}

# parse_config YAML_PATH
# Parses YAML config, outputs normalized JSON
# Requires yq (https://github.com/mikefarah/yq)
parse_config() {
  local config_path="$1"
  
  [[ -f "$config_path" ]] || {
    echo "ERROR: config file not found: $config_path" >&2
    return 1
  }
  
  # Validate YAML syntax
  if ! yq eval '.' "$config_path" >/dev/null 2>&1; then
    echo "ERROR: malformed YAML in $config_path" >&2
    return 1
  fi
  
  # Convert to JSON with required structure
  yq eval -o=json '.' "$config_path" | jq -e '
    has("items") and has("backup") and has("logging") and has("deploy_handoff")
  ' >/dev/null || {
    echo "ERROR: config missing required sections (items, backup, logging, deploy_handoff)" >&2
    return 1
  }
  
  yq eval -o=json '.' "$config_path"
}

# is_manual_item JSON_CONFIG ITEM_NAME
# Returns 0 if item is manual-only, 1 if auto
is_manual_item() {
  local config_json="$1"
  local item_name="$2"
  
  local category
  category="$(echo "$config_json" | jq -r --arg name "$item_name" \
    '.items[] | select(.name == $name) | .category')"
  
  [[ "$category" == "manual" ]]
}

# get_item_config JSON_CONFIG ITEM_NAME
# Returns item config as JSON
get_item_config() {
  local config_json="$1"
  local item_name="$2"
  
  echo "$config_json" | jq -c --arg name "$item_name" \
    '.items[] | select(.name == $name)'
}
