***REMOVED***!/usr/bin/env bash
***REMOVED*** tofu-wrapper.sh — Run tofu with Bitwarden-driven tfvars + backend config.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

***REMOVED*** Render the vault-driven tfvars (and runtime-config.json etc.) on demand.
scripts/fetch_vault.sh

***REMOVED*** Source the env so TF_VAR_* are exported.
***REMOVED*** shellcheck disable=SC1091
. .rendered/vault.env

***REMOVED*** Materialize a -backend-config file from the vault (gitignored).
cat > .rendered/backend.conf <<EOF
bucket                      = "${TOFU_STATE_BUCKET}"
key                         = "infrastructure/terraform.tfstate"
region                      = "${TOFU_STATE_REGION}"
endpoint                    = "${TOFU_STATE_ENDPOINT}"
access_key                  = "${TOFU_STATE_ACCESS_KEY}"
secret_key                  = "${TOFU_STATE_SECRET_KEY}"
skip_region_validation      = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
force_path_style            = true
EOF
chmod 600 .rendered/backend.conf

***REMOVED*** Pre-add rendered files to .gitignore if they are not already ignored.
touch .gitignore
for f in .rendered/terraform.tfvars .rendered/vault.env .rendered/backend.conf .rendered/runtime-config.json; do
  grep -qxF "$f" .gitignore || echo "$f" >> .gitignore
done

***REMOVED*** Pass everything through. Plan/apply/destroy/validate/refresh get the
***REMOVED*** Bitwarden tfvars; init also gets the backend config so
***REMOVED*** credentials/region/bucket come from Bitwarden.
case "${1:-}" in
  init)
    shift
    exec tofu init -backend-config=.rendered/backend.conf "$@"
    ;;
  plan|apply|destroy|validate|refresh)
    exec tofu "$@" -var-file=.rendered/terraform.tfvars
    ;;
  *)
    exec tofu "$@"
    ;;
esac
