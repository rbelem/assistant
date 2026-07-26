#-----------------------------------------------------------------------------
#OpenTofu Remote State Backend — S3-compatible Object Storage
#-----------------------------------------------------------------------------
#Partial backend configuration: bucket, key, region, endpoint and credentials
#are supplied at init time via -backend-config (see tofu/tofu-wrapper.sh).
#
#This keeps the repository environment-agnostic and ready for backend
#migration (currently OVH Object Storage; future Hostinger S3 will use the
#same partial-config pattern).
#
#To create the state bucket first (one-time, before `tofu init`):
#aws s3 mb s3://<your-state-bucket> --endpoint-url <your-s3-endpoint>
#-----------------------------------------------------------------------------

terraform {
  backend "s3" {}
}
