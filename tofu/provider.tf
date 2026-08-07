***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Provider Configuration — Hetzner Cloud + AWS S3 + Cloudflare DNS
***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Hetzner Cloud credentials are sourced from environment variables:
***REMOVED***HCLOUD_TOKEN
***REMOVED***
***REMOVED***AWS/S3 credentials for Object Storage:
***REMOVED***Passed via tofu-inputs variables: storage_access_key, storage_secret_key,
***REMOVED***storage_endpoint, storage_region (and vps_datacenter for AWS region).
***REMOVED***
***REMOVED***Cloudflare DNS (current):
***REMOVED***var.cloudflare_api_token — sourced from Bitwarden Secrets Manager
***REMOVED***(RCLB_DEV_CLOUDFLARE_API_KEY). Requires Zone:Read + Zone:DNS:Edit.
***REMOVED***-----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"  ***REMOVED*** Locked at 1.67.0; bump constraint when upgrading
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

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***AWS S3 Provider — configured for S3-compatible Object Storage
***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Manages S3 buckets on an S3-compatible Object Storage backend (e.g. Hetzner, Backblaze B2, Wasabi).
***REMOVED***Region, endpoint, and credentials are sourced from tofu-inputs variables.
***REMOVED***-----------------------------------------------------------------------------
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

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Porkbun DNS is no longer used — the domain is delegated to Cloudflare.
***REMOVED***The scripts/dns-sync.sh and Porkbun API keys are kept for reference only.
***REMOVED***-----------------------------------------------------------------------------

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Hetzner Cloud Provider
***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Manages the VPS, SSH keys, and DNS-adjacent resources via the Hetzner Cloud API.
***REMOVED***Token sourced from var.hcloud_token (Bitwarden assistant/tofu-inputs).
***REMOVED***-----------------------------------------------------------------------------
provider "hcloud" {
  token = var.hcloud_token
}

***REMOVED***-----------------------------------------------------------------------------
***REMOVED***Cloudflare Provider — DNS record management
***REMOVED***-----------------------------------------------------------------------------
***REMOVED***API token sourced from var.cloudflare_api_token (Bitwarden SM key:
***REMOVED***RCLB_DEV_CLOUDFLARE_API_KEY). Must have Zone:Read + Zone:DNS:Edit
***REMOVED***permissions for the domain zone.
***REMOVED***-----------------------------------------------------------------------------
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
