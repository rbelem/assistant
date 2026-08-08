#-----------------------------------------------------------------------------
#Main Infrastructure — Hetzner Cloud VPS + Cloudflare DNS + Object Storage
#-----------------------------------------------------------------------------
#Resources:
#1. Hetzner Cloud server (Ubuntu 26.04 → converted to NixOS via nixos-infect)
#2. Cloudflare DNS A/CNAME records (see dns.tf) → VPS IP + GitHub Pages
#3. S3 buckets for OpenTofu state and restic backups
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
#Hetzner Cloud Resources
#-----------------------------------------------------------------------------

#Upload SSH key to Hetzner (Tofu-managed). Was data source lookup; tofu apply
#now creates the key in Hetzner so no manual upload step needed.
resource "hcloud_ssh_key" "zet" {
  name       = "zet-agent"
  public_key = var.ssh_public_key
}

#-----------------------------------------------------------------------------
#Hetzner Cloud Server
#-----------------------------------------------------------------------------
#Provisions a server through the Hetzner Cloud API.
#Ubuntu 26.04 is installed first, then converted to NixOS via nixos-infect.
#SSH key is injected inline via Hetzner's first-boot mechanism.
#-----------------------------------------------------------------------------

resource "hcloud_server" "zet" {
  name        = var.vps_display_name
  server_type = var.hcloud_server_type
  image       = var.hcloud_image  # image name (e.g. "ubuntu-26.04") or numeric ID
  location    = var.hcloud_location
  ssh_keys    = [hcloud_ssh_key.zet.id]
  
  labels = {
    project = "zet"
    env     = "production"
  }

  lifecycle {
    #Prevent accidental destruction of the running server (now that initial setup is complete)
    prevent_destroy = true
  }
}

#--- Renames (no destroy/recreate) ----------------------------------------------
#Resource identifiers renamed agent → zet during the project rename; moved
#blocks let tofu update state in place instead of destroying the resources.
moved {
  from = hcloud_ssh_key.agent
  to   = hcloud_ssh_key.zet
}

moved {
  from = hcloud_server.agent
  to   = hcloud_server.zet
}

#-----------------------------------------------------------------------------
#DNS — managed by tofu/dns.tf (Cloudflare provider)
#-----------------------------------------------------------------------------
#Legacy: scripts/dns-sync.sh (Porkbun API) — replaced by Cloudflare provider
#since the domain nameservers point to Cloudflare. See tofu/dns.tf for the
#A record resources.

#-----------------------------------------------------------------------------
#Object Storage — State Bucket Only
#-----------------------------------------------------------------------------
#Backup bucket removed 2026-07-27 (restic backups deferred).
#Only the tofu state bucket remains.
#-----------------------------------------------------------------------------

#--- State bucket (must exist before `tofu init`, import if pre-existing) ---
#First apply needs: tofu import aws_s3_bucket.tofu_state REDACTED-BUCKET
#(run this manually before `tofu apply` if the bucket already exists)
resource "aws_s3_bucket" "tofu_state" {
  bucket = var.state_bucket_name

  #Prevent accidental deletion of the state bucket
  lifecycle {
    prevent_destroy = true
  }
}

#Versioning on the state bucket itself: managed out-of-band on Hetzner Object
#Storage (not via tofu). The aws_s3_bucket_versioning resource failed with
#AccessDenied on PUT to the same bucket it's versioning — circular dependency.
#resource "aws_s3_bucket_versioning" "tofu_state" {
#bucket = aws_s3_bucket.tofu_state.id
#
#versioning_configuration {
#status = "Enabled"
#}
#}

#Public access block on the state bucket itself: same circular dependency as
#versioning — commenting out. The bucket is private by default on Hetzner.
#resource "aws_s3_bucket_public_access_block" "tofu_state" {
#bucket = aws_s3_bucket.tofu_state.id
#
#block_public_acls       = true
#block_public_policy     = true
#ignore_public_acls      = true
#restrict_public_buckets = true
#}

#--- Backup bucket removed 2026-07-27 (restic backups deferred) ---
#Previously: aws_s3_bucket.backups, aws_s3_bucket_versioning.backups,
#aws_s3_bucket_public_access_block.backups — all removed.
#Lifecycle configuration was also commented out (Hetzner doesn't support it).
