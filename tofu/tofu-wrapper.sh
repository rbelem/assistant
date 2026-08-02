***REMOVED***!/usr/bin/env bash
***REMOVED***tofu-wrapper.sh — Run tofu with Bitwarden-driven tfvars + backend config.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOFU_DIR="$REPO_ROOT/tofu"
cd "$REPO_ROOT"

***REMOVED***Render the vault-driven tfvars (and runtime-config.json etc.) on demand.
***REMOVED*** Route fetch_vault's banner to stderr so command substitution of this
***REMOVED*** wrapper's stdout (e.g. `tofu output -raw vps_ip`) yields only the value.
scripts/fetch_vault.sh >&2

***REMOVED***Source the env so TF_VAR_* are exported.
***REMOVED***shellcheck disable=SC1091
. .rendered/vault.env

***REMOVED***Materialize a -backend-config file from the vault (gitignored).
***REMOVED***Use TOFU_STATE_* credential pair (the keys that own the state bucket, separate
***REMOVED***from STORAGE_* which backs the restic data bucket). Region falls back to
***REMOVED***storage_region in case TOFU_STATE_REGION is missing from the vault.
mkdir -p .rendered
BACKEND_REGION="${TOFU_STATE_REGION:-${STORAGE_REGION:-}}"
cat > .rendered/backend.conf <<EOF
bucket                      = "${TOFU_STATE_BUCKET}"
key                         = "infrastructure/terraform.tfstate"
region                      = "${BACKEND_REGION}"
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

***REMOVED***Pre-add rendered files to .gitignore if they are not already ignored.
touch .gitignore
for f in .rendered/terraform.tfvars .rendered/vault.env .rendered/backend.conf .rendered/runtime-config.json; do
  grep -qxF "$f" .gitignore || echo "$f" >> .gitignore
done

***REMOVED***Pass everything through. Plan/apply/destroy/validate/refresh get the
***REMOVED***Bitwarden tfvars; init also gets the backend config so
***REMOVED***credentials/region/bucket come from Bitwarden. All tofu commands run
***REMOVED***from TOFU_DIR (where the *.tf files live); -backend-config and
***REMOVED***-var-file paths are repo-root-relative.
***REMOVED***Note: -var-file is INCOMPATIBLE with applying a saved plan file (tofu
***REMOVED***rejects it because the plan already has variables baked in). Skip
***REMOVED***-var-file when the user passes a positional plan-file arg.
cd "$TOFU_DIR"
case "${1:-}" in
  init)
    shift
    exec tofu init -backend-config="$REPO_ROOT/.rendered/backend.conf" "$@"
    ;;
  plan)
    shift
    exec tofu plan -var-file="$REPO_ROOT/.rendered/terraform.tfvars" "$@"
    ;;
  apply)
    shift
    if [[ $***REMOVED*** -gt 0 && -f "$1" ]]; then
      ***REMOVED*** Positional arg present and it's an existing file (likely a plan file)
      ***REMOVED*** — don't inject -var-file.
      exec tofu apply "$@"
    fi
    exec tofu apply -var-file="$REPO_ROOT/.rendered/terraform.tfvars" "$@"
    ;;
  destroy)
    shift
    exec tofu destroy -var-file="$REPO_ROOT/.rendered/terraform.tfvars" "$@"
    ;;
  validate)
    shift
    exec tofu validate -var-file="$REPO_ROOT/.rendered/terraform.tfvars" "$@"
    ;;
  refresh)
    shift
    exec tofu refresh -var-file="$REPO_ROOT/.rendered/terraform.tfvars" "$@"
    ;;
  *)
    exec tofu "$@"
    ;;
esac
