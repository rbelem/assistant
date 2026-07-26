***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Main Infrastructure — Hetzner Cloud VPS + Porkbun DNS + Object Storage
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Resources:
***REMOVED***   1. Hetzner Cloud server (Ubuntu 26.04 → converted to NixOS via nixos-infect)
***REMOVED***   2. Porkbun DNS A records: wildcard + subdomains → VPS public IP
***REMOVED***   3. S3 buckets for OpenTofu state and restic backups
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hetzner Cloud Resources
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** Upload SSH key to Hetzner (Tofu-managed). Was data source lookup; tofu apply
***REMOVED*** now creates the key in Hetzner so no manual upload step needed.
resource "hcloud_ssh_key" "agent" {
  name       = "assistant-agent"
  public_key = var.ssh_public_key
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hetzner Cloud Server
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Provisions a server through the Hetzner Cloud API.
***REMOVED*** Ubuntu 26.04 is installed first, then converted to NixOS via nixos-infect.
***REMOVED*** SSH key is injected inline via Hetzner's first-boot mechanism.
***REMOVED*** -----------------------------------------------------------------------------

resource "hcloud_server" "agent" {
  name        = var.vps_display_name
  server_type = var.hcloud_server_type
  image       = var.hcloud_image_filter  ***REMOVED*** image name (e.g. "ubuntu-26.04") or numeric ID
  location    = var.hcloud_location
  ssh_keys    = [hcloud_ssh_key.agent.id]
  
  labels = {
    project = "assistant"
    env     = "production"
  }

  lifecycle {
    ***REMOVED*** Prevent accidental destruction of the running server (now that initial setup is complete)
    prevent_destroy = true
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** DNS Records — Porkbun
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Wildcard A record uses the Hetzner server IP; per-subdomain A records are
***REMOVED*** driven by var.subdomains and rendered from Bitwarden.
***REMOVED*** Caddy uses DNS-01 challenge via Porkbun for wildcard TLS certs.
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** resource "porkbun_dns_record" "root_wildcard" {
***REMOVED***   domain    = var.domain_name
***REMOVED***   subdomain = ""      ***REMOVED*** apex
***REMOVED***   type      = "A"
***REMOVED***   content   = hcloud_server.agent.ipv4_address
***REMOVED***   ttl       = var.dns_ttl
***REMOVED*** }
***REMOVED***
***REMOVED*** resource "porkbun_dns_record" "svc" {
***REMOVED***   for_each  = toset(var.subdomains)
***REMOVED***   domain    = var.domain_name
***REMOVED***   subdomain = each.key
***REMOVED***   type      = "A"
***REMOVED***   content   = hcloud_server.agent.ipv4_address
***REMOVED***   ttl       = var.dns_ttl
***REMOVED*** }

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

***REMOVED*** Versioning on the state bucket itself: managed out-of-band on Hetzner Object
***REMOVED*** Storage (not via tofu). The aws_s3_bucket_versioning resource failed with
***REMOVED*** AccessDenied on PUT to the same bucket it's versioning — circular dependency.
***REMOVED*** resource "aws_s3_bucket_versioning" "tofu_state" {
***REMOVED***   bucket = aws_s3_bucket.tofu_state.id
***REMOVED***
***REMOVED***   versioning_configuration {
***REMOVED***     status = "Enabled"
***REMOVED***   }
***REMOVED*** }

***REMOVED*** Public access block on the state bucket itself: same circular dependency as
***REMOVED*** versioning — commenting out. The bucket is private by default on Hetzner.
***REMOVED*** resource "aws_s3_bucket_public_access_block" "tofu_state" {
***REMOVED***   bucket = aws_s3_bucket.tofu_state.id
***REMOVED***
***REMOVED***   block_public_acls       = true
***REMOVED***   block_public_policy     = true
***REMOVED***   ignore_public_acls      = true
***REMOVED***   restrict_public_buckets = true
***REMOVED*** }

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
***REMOVED*** Commented out: Hetzner Object Storage does not support S3 lifecycle configurations.
***REMOVED*** Configure backup retention via restic forget policies in nix-config backup.nix instead.
***REMOVED*** resource "aws_s3_bucket_lifecycle_configuration" "backups" {
***REMOVED***   bucket = aws_s3_bucket.backups.id
***REMOVED***
***REMOVED***   rule {
***REMOVED***     id     = "expire-old-backups"
***REMOVED***     status = "Enabled"
***REMOVED***
***REMOVED***     filter {
***REMOVED***       prefix = ""
***REMOVED***     }
***REMOVED***
***REMOVED***     expiration {
***REMOVED***       days = 90
***REMOVED***     }
***REMOVED***
***REMOVED***     noncurrent_version_expiration {
***REMOVED***       noncurrent_days = 30
***REMOVED***     }
***REMOVED***   }
***REMOVED*** }
