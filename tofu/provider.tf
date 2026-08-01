#-----------------------------------------------------------------------------
#Provider Configuration — Hetzner Cloud + AWS S3 + Porkbun DNS
#-----------------------------------------------------------------------------
#Hetzner Cloud credentials are sourced from environment variables:
#HCLOUD_TOKEN
#
#AWS/S3 credentials for Object Storage:
#Passed via tofu-inputs variables: storage_access_key, storage_secret_key,
#storage_endpoint, storage_region (and vps_datacenter for AWS region).
#
#Porkbun DNS credentials:
#var.porkbun_api_key, var.porkbun_secret_api_key
#(sourced from Bitwarden via TF_VAR_* env vars)
#-----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"  # Locked at 1.67.0; bump constraint when upgrading
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#-----------------------------------------------------------------------------
#AWS S3 Provider — configured for S3-compatible Object Storage
#-----------------------------------------------------------------------------
#Manages S3 buckets on an S3-compatible Object Storage backend (e.g. Hetzner, Backblaze B2, Wasabi).
#Region, endpoint, and credentials are sourced from tofu-inputs variables.
#-----------------------------------------------------------------------------
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

#-----------------------------------------------------------------------------
#Porkbun DNS is managed by scripts/dns-sync.sh (direct API) — the
#marcfrederick/porkbun provider's create path is broken upstream
#(record id returned as object, provider expects int64 — issue #35).
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
#Hetzner Cloud Provider
#-----------------------------------------------------------------------------
#Manages the VPS, SSH keys, and DNS-adjacent resources via the Hetzner Cloud API.
#Token sourced from var.hcloud_token (Bitwarden assistant/tofu-inputs).
#-----------------------------------------------------------------------------
provider "hcloud" {
  token = var.hcloud_token
}
