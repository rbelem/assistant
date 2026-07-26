# -----------------------------------------------------------------------------
# Provider Configuration — Hostinger VPS + AWS S3 + Porkbun DNS
# -----------------------------------------------------------------------------
# Hostinger credentials are sourced from environment variables:
#   HOSTINGER_API_TOKEN
#
# AWS/S3 credentials for Object Storage:
#   Passed via tofu-inputs variables: storage_access_key, storage_secret_key,
#   storage_endpoint, storage_region (and vps_datacenter for AWS region).
#
# Porkbun DNS credentials:
#   PORKBUN_API_KEY, PORKBUN_SECRET_API_KEY
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hostinger = {
      source  = "hostinger/hostinger"
      version = "~> 0.1.22"
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

# -----------------------------------------------------------------------------
# Hostinger Provider
# -----------------------------------------------------------------------------
provider "hostinger" {
  # Credentials sourced from HOSTINGER_API_TOKEN environment variable
}

# -----------------------------------------------------------------------------
# AWS S3 Provider — configured for S3-compatible Object Storage
# -----------------------------------------------------------------------------
# Manages S3 buckets on an S3-compatible Object Storage backend (e.g. OVH).
# Region, endpoint, and credentials are sourced from tofu-inputs variables.
# -----------------------------------------------------------------------------
provider "aws" {
  region     = var.vps_datacenter
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

# -----------------------------------------------------------------------------
# Porkbun DNS Provider
# -----------------------------------------------------------------------------
# Manages DNS records for the configured domain (registered at Porkbun).
# Credentials sourced from PORKBUN_API_KEY and PORKBUN_SECRET_API_KEY env vars.
# -----------------------------------------------------------------------------
provider "porkbun" {
  # Credentials from PORKBUN_API_KEY and PORKBUN_SECRET_API_KEY env vars
}
