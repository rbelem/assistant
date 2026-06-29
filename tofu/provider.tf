***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Provider Configuration — OVH Cloud + AWS S3 (for Object Storage)
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** OVH credentials are sourced from environment variables:
***REMOVED***   OVH_ENDPOINT, OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET,
***REMOVED***   OVH_CONSUMER_KEY
***REMOVED***
***REMOVED*** AWS/S3 credentials for Object Storage:
***REMOVED***   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
***REMOVED*** -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 1.6"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** OVH Provider
***REMOVED*** -----------------------------------------------------------------------------
provider "ovh" {
  ***REMOVED*** Credentials sourced from OVH_* environment variables
  ***REMOVED*** endpoint = "ovh-eu"  ***REMOVED*** Set via OVH_ENDPOINT env var
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** AWS S3 Provider — configured for OVH Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Manages S3 buckets on OVH's S3-compatible Object Storage.
***REMOVED*** Uses the REDACTED-REGION (Gravelines) endpoint by default.
***REMOVED*** -----------------------------------------------------------------------------
provider "aws" {
  region = "gra"

  endpoints {
    s3 = "https://s3.gra.io.REDACTED-OVH-DOMAIN"
  }

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
}
