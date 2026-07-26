***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Main Infrastructure — Hostinger VPS + Porkbun DNS + Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Resources:
***REMOVED***   1. Hostinger VPS instance (NixOS template)
***REMOVED***   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
***REMOVED***   3. S3 buckets for OpenTofu state and restic backups
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Data Sources
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** Discover available VPS plans, data centers, and templates
data "hostinger_vps_plans" "all" {}

data "hostinger_vps_data_centers" "all" {}

data "hostinger_vps_templates" "all" {}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hostinger VPS Instance
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Provisions a VPS through the Hostinger API.
***REMOVED*** The VPS is created with a NixOS template and SSH key access.
***REMOVED*** -----------------------------------------------------------------------------

resource "hostinger_vps" "agent" {
  name             = var.vps_display_name
  plan             = var.hostinger_vps_plan
  data_center_id   = var.hostinger_data_center_id
  template_id      = var.hostinger_template_id
  os               = "NixOS"
  hostname         = "assistant"

  lifecycle {
    ***REMOVED*** Prevent accidental destruction of the running VPS
    ***REMOVED*** Set to true after initial setup is complete
    prevent_destroy = false
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** DNS Records — Porkbun
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Wildcard A record uses the Hostinger VPS IP; per-subdomain A records are
***REMOVED*** driven by var.subdomains / var.vps_ip and rendered from Bitwarden.
***REMOVED*** Caddy uses DNS-01 challenge via Porkbun for wildcard TLS certs.
***REMOVED*** -----------------------------------------------------------------------------

resource "porkbun_dns_record" "root_wildcard" {
  domain    = var.domain_name
  subdomain = ""      ***REMOVED*** apex
  type      = "A"
  content   = hostinger_vps.agent.ipv4
  ttl       = var.dns_ttl
}

resource "porkbun_dns_record" "svc" {
  for_each  = toset(var.subdomains)
  domain    = var.domain_name
  subdomain = each.key
  type      = "A"
  content   = hostinger_vps.agent.ipv4
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
