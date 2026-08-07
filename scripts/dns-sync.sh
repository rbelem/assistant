***REMOVED***!/usr/bin/env bash
***REMOVED*** dns-sync.sh — REPLACED by tofu/dns.tf (Cloudflare provider).
***REMOVED***
***REMOVED*** DNS A records for this project are now managed by OpenTofu via the
***REMOVED*** Cloudflare provider in tofu/dns.tf. Run `tofu apply` from the tofu/
***REMOVED*** directory (or ./scripts/deploy.sh) instead of this script.
***REMOVED***
***REMOVED*** This file is kept for emergency manual reference. The old Porkbun
***REMOVED*** API body was removed 2026-08-06.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "REPLACED by tofu/dns.tf — run 'tofu apply' from tofu/ instead."
  exit 0
fi

echo "dns-sync.sh: REPLACED by tofu/dns.tf (Cloudflare provider)." >&2
echo "  Run: tofu -chdir=\"$REPO_ROOT/tofu\" apply" >&2
exit 0