<<<<<<< HEAD
# -----------------------------------------------------------------------------
# Main Infrastructure — Hetzner Cloud VPS + Porkbun DNS + Object Storage
# -----------------------------------------------------------------------------
# Resources:
#   1. Hetzner Cloud server (Ubuntu 26.04 → converted to NixOS via nixos-infect)
#   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
#   3. S3 buckets for OpenTofu state and restic backups
# -----------------------------------------------------------------------------
||||||| parent of 28e82a5 (fix(deploy): address oracle review blockers)
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Main Infrastructure — Hetzner Cloud VPS + Porkbun DNS + Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Resources:
***REMOVED***   1. Hetzner Cloud server (Ubuntu 22.04 → converted to NixOS via nixos-infect)
***REMOVED***   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
***REMOVED***   3. S3 buckets for OpenTofu state and restic backups
***REMOVED*** -----------------------------------------------------------------------------
=======
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Main Infrastructure — Hetzner Cloud VPS + Porkbun DNS + Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Resources:
***REMOVED***   1. Hetzner Cloud server (Ubuntu 26.04 → converted to NixOS via nixos-infect)
***REMOVED***   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
***REMOVED***   3. S3 buckets for OpenTofu state and restic backups
***REMOVED*** -----------------------------------------------------------------------------
>>>>>>> 28e82a5 (fix(deploy): address oracle review blockers)

# -----------------------------------------------------------------------------
# Hetzner Cloud Resources
# -----------------------------------------------------------------------------

<<<<<<< HEAD
# Upload SSH key to Hetzner (Tofu-managed). Was data source lookup; tofu apply
# now creates the key in Hetzner so no manual upload step needed.
resource "hcloud_ssh_key" "agent" {
  name       = "assistant-agent"
  public_key = var.ssh_public_key
||||||| parent of 28e82a5 (fix(deploy): address oracle review blockers)
***REMOVED*** Discover available server types, locations, and images
data "hetznercloud_server_types" "all" {}

data "hetznercloud_locations" "all" {}

data "hetznercloud_images" "all" {
  most_recent = true
  with_selector = "os-flavor=ubuntu"
  with_architecture = "x86"
=======
***REMOVED*** Discover available server types, locations, and images
data "hetznercloud_server_types" "all" {}

data "hetznercloud_locations" "all" {}

data "hetznercloud_images" "all" {
  most_recent = true
  with_selector = "os-flavor=ubuntu,os-version=26.04"
  with_architecture = "x86"
>>>>>>> 28e82a5 (fix(deploy): address oracle review blockers)
}

# -----------------------------------------------------------------------------
# Hetzner Cloud Server
# -----------------------------------------------------------------------------
# Provisions a server through the Hetzner Cloud API.
# Ubuntu 26.04 is installed first, then converted to NixOS via nixos-infect.
# SSH key is injected inline via Hetzner's first-boot mechanism.
# -----------------------------------------------------------------------------

<<<<<<< HEAD
resource "hcloud_server" "agent" {
||||||| parent of 28e82a5 (fix(deploy): address oracle review blockers)
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hetzner Cloud Server
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Provisions a server through the Hetzner Cloud API.
***REMOVED*** Ubuntu 22.04 is installed first, then converted to NixOS via nixos-infect.
***REMOVED*** SSH key is injected inline via Hetzner's first-boot mechanism.
***REMOVED*** -----------------------------------------------------------------------------

resource "hetznercloud_server" "agent" {
=======
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hetzner Cloud Server
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Provisions a server through the Hetzner Cloud API.
***REMOVED*** Ubuntu 26.04 is installed first, then converted to NixOS via nixos-infect.
***REMOVED*** SSH key is injected inline via Hetzner's first-boot mechanism.
***REMOVED*** -----------------------------------------------------------------------------

resource "hetznercloud_server" "agent" {
>>>>>>> 28e82a5 (fix(deploy): address oracle review blockers)
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

resource "porkbun_dns_record" "root_wildcard" {
  domain    = var.domain_name
  subdomain = ""      # apex
  type      = "A"
  content   = hcloud_server.agent.ipv4_address
  ttl       = var.dns_ttl
}

resource "porkbun_dns_record" "svc" {
  for_each  = toset(var.subdomains)
  domain    = var.domain_name
  subdomain = each.key
  type      = "A"
  content   = hcloud_server.agent.ipv4_address
  ttl       = var.dns_ttl
}

# -----------------------------------------------------------------------------
# Object Storage — State Bucket Only
# -----------------------------------------------------------------------------
# Backup bucket removed 2026-07-27 (restic backups deferred).
# Only the tofu state bucket remains.
# -----------------------------------------------------------------------------

<<<<<<< HEAD
# --- State bucket (must exist before `tofu init`, import if pre-existing) ---
# First apply needs: tofu import aws_s3_bucket.tofu_state assistant-tofu-state
# (run this manually before `tofu apply` if the bucket already exists)
||||||| parent of 28e82a5 (fix(deploy): address oracle review blockers)
***REMOVED*** --- State bucket (must exist before `tofu init`, import if pre-existing) ---
=======
***REMOVED*** --- State bucket (must exist before `tofu init`, import if pre-existing) ---
***REMOVED*** First apply needs: tofu import aws_s3_bucket.tofu_state REDACTED-BUCKET
***REMOVED*** (run this manually before `tofu apply` if the bucket already exists)
>>>>>>> 28e82a5 (fix(deploy): address oracle review blockers)
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

# --- Backup bucket removed 2026-07-27 (restic backups deferred) ---
# Previously: aws_s3_bucket.backups, aws_s3_bucket_versioning.backups,
# aws_s3_bucket_public_access_block.backups — all removed.
# Lifecycle configuration was also commented out (Hetzner doesn't support it).
