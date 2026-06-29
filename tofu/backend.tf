***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** OpenTofu Remote State Backend — OVH S3-compatible Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** State is stored in OVH Object Storage (S3 API) in the REDACTED-REGION (Gravelines) region.
***REMOVED*** Credentials are sourced from environment variables:
***REMOVED***   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION
***REMOVED***
***REMOVED*** To create the bucket first (one-time, before `tofu init`):
***REMOVED***   aws s3 mb s3://rodrigo-agent-tofu-state \
***REMOVED***     --endpoint-url https://s3.gra.io.REDACTED-OVH-DOMAIN
***REMOVED*** -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket = "rodrigo-agent-tofu-state"
    key    = "infrastructure/terraform.tfstate"
    region = "gra"

    ***REMOVED*** OVH S3-compatible endpoint (Gravelines)
    endpoint = "https://s3.gra.io.REDACTED-OVH-DOMAIN"

    ***REMOVED*** S3 compatibility settings required for OVH Object Storage
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    force_path_style            = true
  }
}
