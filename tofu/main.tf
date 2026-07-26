# -----------------------------------------------------------------------------
# Main Infrastructure — Hetzner Cloud VPS + Porkbun DNS + Object Storage
# -----------------------------------------------------------------------------
# Resources:
#   1. Hetzner Cloud server (Ubuntu 26.04 → converted to NixOS via nixos-infect)
#   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
#   3. S3 buckets for OpenTofu state and restic backups
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Hetzner Cloud Resources
# -----------------------------------------------------------------------------

# Upload SSH key to Hetzner (Tofu-managed). Was data source lookup; tofu apply
# now creates the key in Hetzner so no manual upload step needed.
resource "hcloud_ssh_key" "agent" {
  name       = "assistant-agent"
  public_key = var.ssh_public_key
}

# -----------------------------------------------------------------------------
# Hetzner Cloud Server
# -----------------------------------------------------------------------------
# Provisions a server through the Hetzner Cloud API.
# Ubuntu 26.04 is installed first, then converted to NixOS via nixos-infect.
# SSH key is injected inline via Hetzner's first-boot mechanism.
# -----------------------------------------------------------------------------

resource "hcloud_server" "agent" {
  name        = var.vps_display_name
  server_type = var.hcloud_server_type
  image       = var.hcloud_image_filter  # image name (e.g. "ubuntu-26.04") or numeric ID
  location    = var.hcloud_location
  ssh_keys    = [hcloud_ssh_key.agent.id]
  
  labels = {
    project = "assistant"
    env     = "production"
  }

  lifecycle {
    # Prevent accidental destruction of the running server (now that initial setup is complete)
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# DNS Records — Porkbun
# -----------------------------------------------------------------------------
# Wildcard A record uses the Hetzner server IP; per-subdomain A records are
# driven by var.subdomains and rendered from Bitwarden.
# Caddy uses DNS-01 challenge via Porkbun for wildcard TLS certs.
# -----------------------------------------------------------------------------

# resource "porkbun_dns_record" "root_wildcard" {
#   domain    = var.domain_name
#   subdomain = ""      # apex
#   type      = "A"
#   content   = hcloud_server.agent.ipv4_address
#   ttl       = var.dns_ttl
# }
#
# resource "porkbun_dns_record" "svc" {
#   for_each  = toset(var.subdomains)
#   domain    = var.domain_name
#   subdomain = each.key
#   type      = "A"
#   content   = hcloud_server.agent.ipv4_address
#   ttl       = var.dns_ttl
# }

# -----------------------------------------------------------------------------
# Object Storage Buckets (S3-compatible)
# -----------------------------------------------------------------------------
# Two buckets:
#   1. State storage — OpenTofu remote backend
#   2. Backup storage — restic encrypted backups
# -----------------------------------------------------------------------------

# --- State bucket (must exist before `tofu init`, import if pre-existing) ---
# First apply needs: tofu import aws_s3_bucket.tofu_state assistant-tofu-state
# (run this manually before `tofu apply` if the bucket already exists)
resource "aws_s3_bucket" "tofu_state" {
  bucket = var.state_bucket_name

  # Prevent accidental deletion of the state bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning on the state bucket itself: managed out-of-band on Hetzner Object
# Storage (not via tofu). The aws_s3_bucket_versioning resource failed with
# AccessDenied on PUT to the same bucket it's versioning — circular dependency.
# resource "aws_s3_bucket_versioning" "tofu_state" {
#   bucket = aws_s3_bucket.tofu_state.id
#
#   versioning_configuration {
#     status = "Enabled"
#   }
# }

# Public access block on the state bucket itself: same circular dependency as
# versioning — commenting out. The bucket is private by default on Hetzner.
# resource "aws_s3_bucket_public_access_block" "tofu_state" {
#   bucket = aws_s3_bucket.tofu_state.id
#
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }

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
# Commented out: Hetzner Object Storage does not support S3 lifecycle configurations.
# Configure backup retention via restic forget policies in nix-config backup.nix instead.
# resource "aws_s3_bucket_lifecycle_configuration" "backups" {
#   bucket = aws_s3_bucket.backups.id
#
#   rule {
#     id     = "expire-old-backups"
#     status = "Enabled"
#
#     filter {
#       prefix = ""
#     }
#
#     expiration {
#       days = 90
#     }
#
#     noncurrent_version_expiration {
#       noncurrent_days = 30
#     }
#   }
# }
