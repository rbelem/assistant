***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Main Infrastructure — Hetzner Cloud VPS + Porkbun DNS + Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Resources:
***REMOVED***   1. Hetzner Cloud server (Ubuntu 26.04 → converted to NixOS via nixos-infect)
***REMOVED***   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
***REMOVED***   3. S3 buckets for OpenTofu state and restic backups
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Data Sources
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** Discover available server types, locations, and images
data "hetznercloud_server_types" "all" {}

data "hetznercloud_locations" "all" {}

data "hetznercloud_images" "all" {
  most_recent = true
  with_selector = "os-flavor=ubuntu,os-version=26.04"
  with_architecture = "x86"
}

***REMOVED*** Look up SSH key by fingerprint (uploaded to Hetzner out-of-band)
data "hetznercloud_ssh_key" "agent" {
  fingerprint = var.hcloud_ssh_key_fingerprint
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hetzner Cloud Server
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Provisions a server through the Hetzner Cloud API.
***REMOVED*** Ubuntu 26.04 is installed first, then converted to NixOS via nixos-infect.
***REMOVED*** SSH key is injected inline via Hetzner's first-boot mechanism.
***REMOVED*** -----------------------------------------------------------------------------

resource "hetznercloud_server" "agent" {
  name        = var.vps_display_name
  server_type = var.hcloud_server_type
  image       = data.hetznercloud_images.all.images[0].id
  location    = var.hcloud_location
  ssh_keys    = [data.hetznercloud_ssh_key.agent.id]
  
  labels = {
    project = "assistant"
    env     = "production"
  }

  lifecycle {
    ***REMOVED*** Prevent accidental destruction of the running server
    ***REMOVED*** Set to true after initial setup is complete
    prevent_destroy = false
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** DNS Records — Porkbun
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Wildcard A record uses the Hetzner server IP; per-subdomain A records are
***REMOVED*** driven by var.subdomains and rendered from Bitwarden.
***REMOVED*** Caddy uses DNS-01 challenge via Porkbun for wildcard TLS certs.
***REMOVED*** -----------------------------------------------------------------------------

resource "porkbun_dns_record" "root_wildcard" {
  domain    = var.domain_name
  subdomain = ""      ***REMOVED*** apex
  type      = "A"
  content   = hetznercloud_server.agent.ipv4_address
  ttl       = var.dns_ttl
}

resource "porkbun_dns_record" "svc" {
  for_each  = toset(var.subdomains)
  domain    = var.domain_name
  subdomain = each.key
  type      = "A"
  content   = hetznercloud_server.agent.ipv4_address
  ttl       = var.dns_ttl
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Object Storage Buckets (S3-compatible)
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Two buckets:
***REMOVED***   1. State storage — OpenTofu remote backend
***REMOVED***   2. Backup storage — restic encrypted backups
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** --- State bucket (must exist before `tofu init`, import if pre-existing) ---
***REMOVED*** First apply needs: tofu import aws_s3_bucket.tofu_state REDACTED-BUCKET
***REMOVED*** (run this manually before `tofu apply` if the bucket already exists)
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
