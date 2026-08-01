***REMOVED***!/usr/bin/env bash
***REMOVED*** dns-sync.sh — sync Porkbun DNS A records to the VPS IP via the direct API.
***REMOVED***
***REMOVED*** Why not the tofu provider: marcfrederick/porkbun's create path is broken
***REMOVED*** upstream (the API returns the record id as an object; the provider parses it
***REMOVED*** as int64 — issue ***REMOVED***35, unfixed as of v1.3.3). DNS is therefore managed with
***REMOVED*** the raw Porkbun API instead.
***REMOVED***
***REMOVED*** Ensures an A record for the apex domain and every subdomain points at the
***REMOVED*** VPS IP. Idempotent: edits existing records whose content differs, creates
***REMOVED*** missing ones. Safe to run on every deploy.
***REMOVED***
***REMOVED*** Usage:
***REMOVED***   scripts/dns-sync.sh              ***REMOVED*** sync apex + subdomains to VPS IP
***REMOVED***   scripts/dns-sync.sh --help       ***REMOVED*** this message
***REMOVED***
***REMOVED*** Environment (all from .rendered/vault.env when present):
***REMOVED***   PORKBUN_API_KEY, PORKBUN_SECRET_API_KEY   API credentials
***REMOVED***   DOMAIN, SUBDOMAINS_JSON                   what to sync (apex + subdomains)
***REMOVED***   VPS_IP | VPS_HOST                         target IP (default: tofu output)
***REMOVED***   DNS_TTL                                   TTL seconds (default: 600)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

API="https://api.porkbun.com/api/json/v3"
TTL="${DNS_TTL:-600}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^$/p' "$0" | sed 's/^***REMOVED*** \?//'
  exit 0
fi

***REMOVED*** Load vault-derived env (PORKBUN_API_KEY, PORKBUN_SECRET_API_KEY, DOMAIN, SUBDOMAINS_JSON)
***REMOVED*** shellcheck disable=SC1091
[[ -f "$REPO_ROOT/.rendered/vault.env" ]] && . "$REPO_ROOT/.rendered/vault.env"

***REMOVED*** --- resolve IP -------------------------------------------------------------
IP="${VPS_IP:-}"
if [[ -z "$IP" || "$IP" == "TBD.pending.tofu.apply" ]]; then
  IP="$(tofu -chdir="$REPO_ROOT/tofu" output -raw vps_ip 2>/dev/null || true)"
fi
if [[ -z "$IP" || "$IP" == "TBD.pending.tofu.apply" ]]; then
  IP="${VPS_HOST:-}"
fi
if [[ -z "$IP" || "$IP" == "TBD.pending.tofu.apply" ]]; then
  echo "dns-sync: cannot resolve VPS IP (set VPS_IP or run after tofu apply)" >&2
  exit 1
fi

DOMAIN="${DOMAIN:-}"
if [[ -z "$DOMAIN" ]]; then
  echo "dns-sync: DOMAIN not set (source .rendered/vault.env)" >&2
  exit 1
fi

***REMOVED*** --- helpers ----------------------------------------------------------------
post() {  ***REMOVED*** post <path> <json-body>
  curl -sS -X POST "$API/$1" -H 'Content-Type: application/json' -d "$2"
}

auth_json() {
  jq -n --arg k "${PORKBUN_API_KEY:-}" --arg s "${PORKBUN_SECRET_API_KEY:-}" \
    '{secretapikey: $s, apikey: $k}'
}

***REMOVED*** --- fetch current records --------------------------------------------------
records_json="$(post "dns/retrieve/$DOMAIN" "$(auth_json)")"
if [[ "$(echo "$records_json" | jq -r '.status // "ERROR"')" != "SUCCESS" ]]; then
  echo "dns-sync: Porkbun retrieve failed: $(echo "$records_json" | jq -r '.message // .' | head -c 200)" >&2
  exit 1
fi

***REMOVED*** --- build target list: apex + each subdomain -------------------------------
TARGETS=("$DOMAIN")
while IFS= read -r s; do
  [[ -n "$s" ]] && TARGETS+=("$s.$DOMAIN")
done < <(echo "${SUBDOMAINS_JSON:-[]}" | jq -r '.[]' 2>/dev/null || true)

***REMOVED*** --- ensure each record -----------------------------------------------------
***REMOVED*** Porkbun's edit endpoint is broken upstream (returns
***REMOVED*** EDIT_ERROR_WE_WERE_UNABLE_TO_EDIT_THE_DNS_RECORD for every request), so we
***REMOVED*** reconcile with delete + create instead: keep exactly one A record per name
***REMOVED*** pointing at the target IP, dropping stale duplicates.
rc=0
for name in "${TARGETS[@]}"; do
  ***REMOVED*** all A records for this name (apex records carry the bare domain as name)
  mapfile -t recs < <(echo "$records_json" | jq -c --arg n "$name" '.records[] | select(.type == "A" and .name == $n)')

  has_match=""
  stale_ids=()
  for rec in "${recs[@]:-}"; do
    [[ -z "$rec" ]] && continue
    if [[ "$(echo "$rec" | jq -r '.content')" == "$IP" ]]; then
      has_match="1"
    else
      stale_ids+=("$(echo "$rec" | jq -r '.id')")
    fi
  done

  ***REMOVED*** drop stale duplicates first
  for id in "${stale_ids[@]:-}"; do
    [[ -n "$id" ]] || continue
    resp="$(post "dns/delete/$DOMAIN/$id" "$(auth_json)")"
    if [[ "$(echo "$resp" | jq -r '.status // "ERROR"')" == "SUCCESS" ]]; then
      echo "dns-sync: deleted stale A $name (id $id)"
    else
      echo "dns-sync: delete A $name (id $id) FAILED: $(echo "$resp" | jq -r '.message // .' | head -c 200)" >&2
      rc=1
    fi
  done

  if [[ -n "$has_match" ]]; then
    echo "dns-sync: ok A $name -> $IP (unchanged)"
    continue
  fi

  ***REMOVED*** create — name is the label (empty for apex)
  label="${name%.$DOMAIN}"
  body="$(auth_json | jq --arg n "$label" --arg ip "$IP" --arg ttl "$TTL" \
    '. + {name: $n, type: "A", content: $ip, ttl: $ttl}')"
  resp="$(post "dns/create/$DOMAIN" "$body")"
  if [[ "$(echo "$resp" | jq -r '.status // "ERROR"')" == "SUCCESS" ]]; then
    echo "dns-sync: created A $name -> $IP"
  else
    echo "dns-sync: create A $name FAILED: $(echo "$resp" | jq -r '.message // .' | head -c 200)" >&2
    rc=1
  fi
done

exit "$rc"
