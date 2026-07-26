***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** OpenTofu Remote State Backend — S3-compatible Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Partial backend configuration: bucket, key, region, endpoint and credentials
***REMOVED*** are supplied at init time via -backend-config (see tofu/tofu-wrapper.sh).
***REMOVED***
***REMOVED*** This keeps the repository environment-agnostic and ready for backend
***REMOVED*** migration (currently OVH Object Storage; future Hostinger S3 will use the
***REMOVED*** same partial-config pattern).
***REMOVED***
***REMOVED*** To create the state bucket first (one-time, before `tofu init`):
***REMOVED***   aws s3 mb s3://<your-state-bucket> --endpoint-url <your-s3-endpoint>
***REMOVED*** -----------------------------------------------------------------------------

terraform {
  backend "s3" {}
}
