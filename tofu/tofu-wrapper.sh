#!/usr/bin/env bash
# tofu-wrapper.sh — Run tofu with Bitwarden-driven tfvars + backend config.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Render the vault-driven tfvars (and runtime-config.json etc.) on demand.
scripts/fetch_vault.sh

# Source the env so TF_VAR_* are exported.
# shellcheck disable=SC1091
. .rendered/vault.env

# Materialize a -backend-config file from the vault (gitignored).
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

# Pre-add rendered files to .gitignore if they are not already ignored.
touch .gitignore
for f in .rendered/terraform.tfvars .rendered/vault.env .rendered/backend.conf .rendered/runtime-config.json; do
  grep -qxF "$f" .gitignore || echo "$f" >> .gitignore
done

# Pass everything through. Plan/apply/destroy/validate/refresh get the
# Bitwarden tfvars; init also gets the backend config so
# credentials/region/bucket come from Bitwarden.
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
