***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Main Infrastructure — OVH VPS + Porkbun DNS + Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Resources:
***REMOVED***   1. OVH VPS instance (Debian 12 → converted to NixOS via nixos-infect)
***REMOVED***   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
***REMOVED***   3. S3 buckets for OpenTofu state and restic backups
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Data Sources
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** Fetch OVH account info (needed for ovh_subsidiary on VPS order)
data "ovh_me" "account" {}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** OVH VPS Instance
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Orders a VPS through the OVH API using the order-based model.
***REMOVED*** After provisioning, convert to NixOS with nixos-infect:
***REMOVED***   1. ssh debian@<vps_ip>
***REMOVED***   2. curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | sudo bash
***REMOVED***   3. Reboot into NixOS
***REMOVED***
***REMOVED*** NOTE: To use public_ssh_key, image_id must also be set.
***REMOVED*** The image_id can be found via the OVH API:
***REMOVED***   GET /vps/{serviceName}/images/available
***REMOVED*** Or use a known Debian 12 image ID for your region.
***REMOVED*** -----------------------------------------------------------------------------

resource "ovh_vps" "agent" {
  display_name    = var.vps_display_name
  ovh_subsidiary  = data.ovh_me.account.ovh_subsidiary
  netboot_mode    = "local"

  ***REMOVED*** SSH key and image_id must both be set together (OVH API requirement)
  ***REMOVED*** If not provided, the VPS is created with default credentials (sent by email)
  public_ssh_key = var.ssh_public_key != "" ? var.ssh_public_key : null
  image_id       = var.vps_image_id != "" ? var.vps_image_id : null

  ***REMOVED*** VPS plan configuration
  plan = [
    {
      duration     = "P1M"
      plan_code    = var.vps_plan_code
      pricing_mode = "default"

      configuration = [
        {
          label = "vps_datacenter"
          value = var.vps_datacenter
        },
        {
          label = "vps_os"
          value = var.vps_os
        }
      ]
    }
  ]

  lifecycle {
    ***REMOVED*** Prevent accidental destruction of the running VPS
    ***REMOVED*** Set to true after initial setup is complete
    prevent_destroy = false
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Data Source — Fetch VPS details (including IPs)
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** The ovh_vps resource doesn't expose IPs directly as computed attributes.
***REMOVED*** We use a data source to retrieve them after the VPS is provisioned.
***REMOVED*** This creates an implicit dependency on the resource.
***REMOVED*** -----------------------------------------------------------------------------

data "ovh_vps" "agent_details" {
  service_name = ovh_vps.agent.service_name
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** DNS Records — Porkbun
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Wildcard A record uses the data source IP; per-subdomain A records are
***REMOVED*** driven by var.subdomains / var.vps_ip and rendered from Bitwarden.
***REMOVED*** Caddy uses DNS-01 challenge via Porkbun for wildcard TLS certs.
***REMOVED*** -----------------------------------------------------------------------------

resource "porkbun_dns_record" "root_wildcard" {
  domain    = var.domain_name
  subdomain = ""      ***REMOVED*** apex
  type      = "A"
  content   = var.vps_ip
  ttl       = var.dns_ttl
}

resource "porkbun_dns_record" "svc" {
  for_each  = toset(var.subdomains)
  domain    = var.domain_name
  subdomain = each.key
  type      = "A"
  content   = var.vps_ip
  ttl       = var.dns_ttl
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Object Storage Buckets (OVH S3-compatible)
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Two buckets:
***REMOVED***   1. State storage — OpenTofu remote backend
***REMOVED***   2. Backup storage — restic encrypted backups
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** --- State bucket (must exist before `tofu init`, import if pre-existing) ---
resource "aws_s3_bucket" "tofu_state" {
  bucket = var.state_bucket_name

  ***REMOVED*** Prevent accidental deletion of the state bucket
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tofu_state" {
  bucket = aws_s3_bucket.tofu_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tofu_state" {
  bucket = aws_s3_bucket.tofu_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

***REMOVED*** --- Backup bucket for restic ---
resource "aws_s3_bucket" "backups" {
  bucket = var.backup_bucket_name
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

***REMOVED*** Lifecycle: expire old backup versions after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
