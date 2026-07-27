#!/usr/bin/env bats
# rotate-secrets.bats — tests for pure functions in rotate-secrets.lib.sh
#
# Run: bats tests/rotate-secrets.bats
# Requires: bats-core (https://github.com/bats-core/bats-core)

setup() {
  # Source the library under test
  source "$BATS_TEST_DIRNAME/../scripts/rotate-secrets.lib.sh"
}

#--- age_days() ---------------------------------------------------------------
@test "age_days: returns 0 for current timestamp" {
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local result
  result="$(age_days "$now")"
  [[ "$result" -eq 0 ]]
}

@test "age_days: returns positive for past timestamp" {
  local past
  past="$(date -u -d '10 days ago' +%Y-%m-%dT%H:%M:%SZ)"
  local result
  result="$(age_days "$past")"
  [[ "$result" -ge 9 && "$result" -le 11 ]]
}

@test "age_days: returns negative for future timestamp" {
  local future
  future="$(date -u -d '5 days' +%Y-%m-%dT%H:%M:%SZ)"
  local result
  result="$(age_days "$future")"
  [[ "$result" -le -4 && "$result" -ge -6 ]]
}

@test "age_days: fails on invalid timestamp" {
  run age_days "not-a-timestamp"
  [[ "$status" -ne 0 ]]
}

#--- gen_hex() ----------------------------------------------------------------
@test "gen_hex: returns 2*N hex chars for N bytes" {
  local result
  result="$(gen_hex 16)"
  [[ "${#result}" -eq 32 ]]
  [[ "$result" =~ ^[0-9a-f]+$ ]]
}

@test "gen_hex: returns 64 hex chars for 32 bytes" {
  local result
  result="$(gen_hex 32)"
  [[ "${#result}" -eq 64 ]]
  [[ "$result" =~ ^[0-9a-f]+$ ]]
}

#--- gen_base64() -------------------------------------------------------------
@test "gen_base64: returns valid base64 without padding" {
  local result
  result="$(gen_base64 32)"
  [[ -n "$result" ]]
  # No padding chars
  [[ "$result" != *"="* ]]
  # No newlines
  [[ "$result" != *$'\n'* ]]
  # Valid base64 chars
  [[ "$result" =~ ^[A-Za-z0-9+/]+$ ]]
}

#--- gen_password_diceware() --------------------------------------------------
@test "gen_password_diceware: returns N space-separated words" {
  # Skip if wordlist not available
  [[ -f /usr/share/dict/words ]] || skip "/usr/share/dict/words not found"

  local result
  result="$(gen_password_diceware 6)"
  local word_count
  word_count="$(echo "$result" | wc -w)"
  [[ "$word_count" -eq 6 ]]
}

@test "gen_password_diceware: returns 4 words when requested" {
  [[ -f /usr/share/dict/words ]] || skip "/usr/share/dict/words not found"

  local result
  result="$(gen_password_diceware 4)"
  local word_count
  word_count="$(echo "$result" | wc -w)"
  [[ "$word_count" -eq 4 ]]
}

@test "gen_password_diceware: fails without wordlist" {
  # Temporarily rename wordlist if it exists
  if [[ -f /usr/share/dict/words ]]; then
    skip "wordlist exists, cannot test failure path"
  fi

  run gen_password_diceware 6
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"wordlist not found"* ]]
}

#--- history_append() ---------------------------------------------------------
@test "history_append: adds entry to empty array" {
  local result
  result="$(history_append "[]" "test/item" "b2xk" "2024-01-01T00:00:00Z" "test")"
  local count
  count="$(echo "$result" | jq 'length')"
  [[ "$count" -eq 1 ]]

  local item
  item="$(echo "$result" | jq -r '.[0].item')"
  [[ "$item" == "test/item" ]]
}

@test "history_append: adds entry to existing array" {
  local existing='[{"item":"a","old_value_b64":"x","rotated_at":"2024-01-01T00:00:00Z","by":"test"}]'
  local result
  result="$(history_append "$existing" "b" "eQ==" "2024-01-02T00:00:00Z" "test")"
  local count
  count="$(echo "$result" | jq 'length')"
  [[ "$count" -eq 2 ]]
}

@test "history_append: fails on invalid JSON" {
  run history_append "not-json" "item" "val" "ts" "by"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"invalid JSON"* ]]
}

#--- history_trim() -----------------------------------------------------------
@test "history_trim: keeps N most recent entries per item" {
  # Create array with 6 entries for same item
  local json='[]'
  for i in {1..6}; do
    json="$(echo "$json" | jq -c --arg i "$i" \
      '. + [{item:"test/item",old_value_b64:"x",rotated_at:"2024-01-0\($i)T00:00:00Z",by:"test"}]')"
  done

  local result
  result="$(history_trim "$json" "test/item" 5)"
  local count
  count="$(echo "$result" | jq '[.[] | select(.item == "test/item")] | length')"
  [[ "$count" -eq 5 ]]
}

@test "history_trim: preserves entries for other items" {
  local json='[
    {"item":"a","old_value_b64":"x","rotated_at":"2024-01-01T00:00:00Z","by":"test"},
    {"item":"b","old_value_b64":"y","rotated_at":"2024-01-01T00:00:00Z","by":"test"},
    {"item":"a","old_value_b64":"z","rotated_at":"2024-01-02T00:00:00Z","by":"test"}
  ]'

  local result
  result="$(history_trim "$json" "a" 1)"

  # Should have 1 entry for "a" and 1 for "b"
  local a_count b_count
  a_count="$(echo "$result" | jq '[.[] | select(.item == "a")] | length')"
  b_count="$(echo "$result" | jq '[.[] | select(.item == "b")] | length')"
  [[ "$a_count" -eq 1 ]]
  [[ "$b_count" -eq 1 ]]
}

@test "history_trim: fails on invalid JSON" {
  run history_trim "bad-json" "item" 5
  [[ "$status" -ne 0 ]]
}

#--- parse_config() -----------------------------------------------------------
@test "parse_config: succeeds with valid config" {
  local config_path="$BATS_TEST_DIRNAME/../scripts/rotate-secrets.conf"
  [[ -f "$config_path" ]] || skip "config not found"

  run parse_config "$config_path"
  [[ "$status" -eq 0 ]]

  # Verify structure
  echo "$output" | jq -e 'has("items")' >/dev/null
  echo "$output" | jq -e 'has("backup")' >/dev/null
  echo "$output" | jq -e 'has("logging")' >/dev/null
  echo "$output" | jq -e 'has("deploy_handoff")' >/dev/null
}

@test "parse_config: fails with missing file" {
  run parse_config "/nonexistent/path.yml"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not found"* ]]
}

@test "parse_config: fails with malformed YAML" {
  local tmp
  tmp="$(mktemp)"
  echo "invalid: yaml: [unclosed" > "$tmp"

  run parse_config "$tmp"
  rm -f "$tmp"

  [[ "$status" -ne 0 ]]
}

#--- is_manual_item() ---------------------------------------------------------
@test "is_manual_item: returns 0 for manual category" {
  local config_json
  config_json="$(parse_config "$BATS_TEST_DIRNAME/../scripts/rotate-secrets.conf")"

  is_manual_item "$config_json" "assistant/restic-backup-password"
}

@test "is_manual_item: returns 1 for auto category" {
  local config_json
  config_json="$(parse_config "$BATS_TEST_DIRNAME/../scripts/rotate-secrets.conf")"

  run is_manual_item "$config_json" "assistant/zitadel-admin-password"
  [[ "$status" -eq 1 ]]
}

#--- get_item_config() --------------------------------------------------------
@test "get_item_config: returns item config as JSON" {
  local config_json
  config_json="$(parse_config "$BATS_TEST_DIRNAME/../scripts/rotate-secrets.conf")"

  local result
  result="$(get_item_config "$config_json" "assistant/zitadel-admin-password")"

  [[ -n "$result" ]]
  echo "$result" | jq -e '.name == "assistant/zitadel-admin-password"' >/dev/null
  echo "$result" | jq -e '.generator == "password"' >/dev/null
  echo "$result" | jq -e '.category == "auto"' >/dev/null
}

@test "get_item_config: returns empty for unknown item" {
  local config_json
  config_json="$(parse_config "$BATS_TEST_DIRNAME/../scripts/rotate-secrets.conf")"

  local result
  result="$(get_item_config "$config_json" "nonexistent/item")"
  [[ -z "$result" || "$result" == "null" ]]
}
