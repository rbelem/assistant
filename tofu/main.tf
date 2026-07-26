# -----------------------------------------------------------------------------
# Main Infrastructure — Hostinger VPS + Porkbun DNS + Object Storage
# -----------------------------------------------------------------------------
# Resources:
#   1. Hostinger VPS instance (NixOS template)
#   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
#   3. S3 buckets for OpenTofu state and restic backups
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Discover available VPS plans, data centers, and templates
data "hostinger_vps_plans" "all" {}

data "hostinger_vps_data_centers" "all" {}

data "hostinger_vps_templates" "all" {}

# -----------------------------------------------------------------------------
# Hostinger VPS Instance
# -----------------------------------------------------------------------------
# Provisions a VPS through the Hostinger API.
# The VPS is created with a NixOS template and SSH key access.
# -----------------------------------------------------------------------------

resource "hostinger_vps" "agent" {
  name             = var.vps_display_name
  plan             = var.hostinger_vps_plan
  data_center_id   = var.hostinger_data_center_id
  template_id      = var.hostinger_template_id
  os               = "NixOS"
  hostname         = "assistant"

  lifecycle {
    # Prevent accidental destruction of the running VPS
    # Set to true after initial setup is complete
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# DNS Records — Porkbun
# -----------------------------------------------------------------------------
# Wildcard A record uses the Hostinger VPS IP; per-subdomain A records are
# driven by var.subdomains / var.vps_ip and rendered from Bitwarden.
# Caddy uses DNS-01 challenge via Porkbun for wildcard TLS certs.
# -----------------------------------------------------------------------------

resource "porkbun_dns_record" "root_wildcard" {
  domain    = var.domain_name
  subdomain = ""      # apex
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

# -----------------------------------------------------------------------------
# Object Storage Buckets (OVH S3-compatible)
# -----------------------------------------------------------------------------
# Two buckets:
#   1. State storage — OpenTofu remote backend
#   2. Backup storage — restic encrypted backups
# -----------------------------------------------------------------------------

# --- State bucket (must exist before `tofu init`, import if pre-existing) ---
resource "aws_s3_bucket" "tofu_state" {
  bucket = var.state_bucket_name

  # Prevent accidental deletion of the state bucket
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

# --- Backup bucket for restic ---
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

# Lifecycle: expire old backup versions after 90 days
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
