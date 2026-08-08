#-----------------------------------------------------------------------------
#Provider Configuration — Hetzner Cloud + AWS S3 + Cloudflare DNS
#-----------------------------------------------------------------------------
#Hetzner Cloud credentials are sourced from environment variables:
#HCLOUD_TOKEN
#
#AWS/S3 credentials for Object Storage:
#Passed via tofu-inputs variables: storage_access_key, storage_secret_key,
#storage_endpoint, storage_region (and vps_datacenter for AWS region).
#
#Cloudflare DNS (current):
#var.cloudflare_api_token — sourced from Bitwarden Secrets Manager
#(RCLB_DEV_CLOUDFLARE_API_KEY). Requires Zone:Read + Zone:DNS:Edit.
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

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
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
#Porkbun DNS is no longer used — the domain is delegated to Cloudflare.
#The scripts/dns-sync.sh and Porkbun API keys are kept for reference only.
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
#Hetzner Cloud Provider
#-----------------------------------------------------------------------------
#Manages the VPS, SSH keys, and DNS-adjacent resources via the Hetzner Cloud API.
#Token sourced from var.hcloud_token (Bitwarden zet/tofu-inputs).
#-----------------------------------------------------------------------------
provider "hcloud" {
  token = var.hcloud_token
}

#-----------------------------------------------------------------------------
#Cloudflare Provider — DNS record management
#-----------------------------------------------------------------------------
#API token sourced from var.cloudflare_api_token (Bitwarden SM key:
#RCLB_DEV_CLOUDFLARE_API_KEY). Must have Zone:Read + Zone:DNS:Edit
#permissions for the domain zone.
#-----------------------------------------------------------------------------
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
