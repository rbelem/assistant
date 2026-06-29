***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Input Variables — OVH VPS + Infrastructure Configuration
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Override defaults via terraform.tfvars, -var flags, or TF_VAR_* env vars.
***REMOVED*** Sensitive values (API keys) should be set via environment variables.
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** OVH Account
***REMOVED*** -----------------------------------------------------------------------------

variable "ovh_subsidiary" {
  description = "OVHcloud subsidiary (country code for billing: FR, DE, GB, etc.)"
  type        = string
  default     = "FR"
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** VPS Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "vps_display_name" {
  description = "Display name for the VPS in OVH Manager"
  type        = string
  default     = "rodrigo-agent"
}

variable "vps_datacenter" {
  description = "OVH datacenter for the VPS (e.g. REDACTED-REGION1, REDACTED-REGION1, REDACTED-REGION1)"
  type        = string
  default     = "REDACTED-REGION1"
}

variable "vps_plan_code" {
  description = "OVH VPS plan code (REDACTED-PLAN = 2 vCPU, 2GB RAM, 40GB SSD)"
  type        = string
  default     = "REDACTED-PLAN"
}

variable "vps_os" {
  description = "Operating system for the VPS (configured via plan.configuration)"
  type        = string
  default     = "Debian 12"
}

variable "ssh_public_key" {
  description = "SSH public key to pre-install on the VPS (full key string, e.g. 'ssh-ed25519 AAAA...')"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vps_image_id" {
  description = "Image ID to install on the VPS (required if ssh_public_key is set). Find available IDs via: GET /vps/{serviceName}/images/available"
  type        = string
  default     = ""
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** DNS Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Base domain name (must be managed by OVH DNS zone)"
  type        = string
  default     = "REDACTED-DOMAIN"
}

variable "subdomain" {
  description = "Subdomain prefix for the VPS DNS record"
  type        = string
  default     = "agent"
}

variable "dns_ttl" {
  description = "DNS record TTL in seconds (minimum 60)"
  type        = number
  default     = 300

  validation {
    condition     = var.dns_ttl >= 60 && var.dns_ttl <= 86400
    error_message = "TTL must be between 60 and 86400 seconds."
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Object Storage Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "state_bucket_name" {
  description = "S3 bucket name for OpenTofu remote state"
  type        = string
  default     = "rodrigo-agent-tofu-state"
}

variable "backup_bucket_name" {
  description = "S3 bucket name for restic backups"
  type        = string
  default     = "rodrigo-agent-backups"
}

variable "storage_region" {
  description = "OVH Object Storage region identifier (gra, sbg, etc.)"
  type        = string
  default     = "gra"
}
