***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Provider Configuration — Hetzner Cloud + AWS S3 + Porkbun DNS
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hetzner Cloud credentials are sourced from environment variables:
***REMOVED***   HCLOUD_TOKEN
***REMOVED***
***REMOVED*** AWS/S3 credentials for Object Storage:
***REMOVED***   Passed via tofu-inputs variables: storage_access_key, storage_secret_key,
***REMOVED***   storage_endpoint, storage_region (and vps_datacenter for AWS region).
***REMOVED***
***REMOVED*** Porkbun DNS credentials:
***REMOVED***   PORKBUN_API_KEY, PORKBUN_SECRET_API_KEY
***REMOVED*** -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hetznercloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"  ***REMOVED*** Pinned to 1.45.x line (Q1 2026 stable)
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    porkbun = {
      source  = "marcfrederick/porkbun"
      version = "~> 1.3"
    }
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** AWS S3 Provider — configured for S3-compatible Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Manages S3 buckets on an S3-compatible Object Storage backend (e.g. Hetzner, Backblaze B2, Wasabi).
***REMOVED*** Region, endpoint, and credentials are sourced from tofu-inputs variables.
***REMOVED*** -----------------------------------------------------------------------------
provider "aws" {
  region     = var.storage_region
  access_key = var.storage_access_key
  secret_key = var.storage_secret_key

  endpoints {
    s3 = var.storage_endpoint
  }

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Porkbun DNS Provider
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Manages DNS records for the configured domain (registered at Porkbun).
***REMOVED*** Credentials sourced from PORKBUN_API_KEY and PORKBUN_SECRET_API_KEY env vars.
***REMOVED*** -----------------------------------------------------------------------------
provider "porkbun" {
  ***REMOVED*** Credentials from PORKBUN_API_KEY and PORKBUN_SECRET_API_KEY env vars
}
