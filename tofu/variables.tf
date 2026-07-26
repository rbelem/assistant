***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Input Variables — OVH VPS + Infrastructure Configuration
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Values are sourced from Bitwarden via scripts/fetch_vault.sh, which renders:
***REMOVED***   .rendered/terraform.tfvars   (tfvars passed via tofu-wrapper.sh)
***REMOVED***   .rendered/vault.env          (TF_VAR_* env vars)
***REMOVED*** No environment-specific defaults are committed in this public repo.
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** VPS Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "vps_display_name" {
  description = "Display name for the VPS in OVH Manager. Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = length(var.vps_display_name) > 0
    error_message = "VPS display name must not be empty."
  }
}

***REMOVED*** Supported VPS providers: OVH (REDACTED-PLAN / REDACTED-REGION1) and Hostinger
***REMOVED*** (hostingercom-vps-kvm4-... / curitiba). Validation accepts both patterns.
variable "vps_datacenter" {
  description = "VPS datacenter/region (e.g. REDACTED-REGION1, REDACTED-REGION1, curitiba). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{2,16}$", var.vps_datacenter))
    error_message = "Datacenter/region must be 2-16 alphanumeric characters, underscores, or hyphens."
  }
}

variable "vps_plan_code" {
  description = "VPS plan code (e.g. REDACTED-PLAN). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+$", var.vps_plan_code))
    error_message = "VPS plan code must be lowercase letters, digits, and hyphens."
  }
}

variable "vps_os" {
  description = "Operating system for the VPS (configured via plan.configuration). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = length(var.vps_os) > 0
    error_message = "VPS OS must not be empty."
  }
}

variable "ssh_public_key" {
  description = "SSH public key to pre-install on the VPS (full key string, e.g. 'ssh-ed25519 AAAA...'). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string
  sensitive   = true

  validation {
    condition     = var.ssh_public_key == "" || can(regex("^ssh-(rsa|ed25519|dss|ecdsa) ", var.ssh_public_key))
    error_message = "SSH public key must be empty (OVH emailed credentials) or a valid ssh-rsa/ed25519/dss/ecdsa public key."
  }
}

variable "vps_image_id" {
  description = "Image ID to install on the VPS (required if ssh_public_key is set). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = var.vps_image_id == "" || can(regex("^[0-9a-fA-F-]{36}$", var.vps_image_id))
    error_message = "Image ID must be empty or a valid UUID."
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** DNS Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Base domain name (managed by Porkbun DNS). Source: Bitwarden rodrigo-agent/domain-config"
  type        = string

  validation {
    condition     = length(regexall("\\.", var.domain_name)) > 0
    error_message = "Domain name must contain at least one dot (e.g. example.com)."
  }
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

variable "subdomains" {
  type        = list(string)
  description = "Subdomain list (per-service A records). Source: Bitwarden rodrigo-agent/domain-config"

  validation {
    condition     = length(var.subdomains) > 0 && alltrue([for s in var.subdomains : length(s) > 0 && !can(regex("\\.", s))])
    error_message = "subdomains must be a non-empty list of single-label hostnames (no dots)."
  }
}

variable "vps_ip" {
  description = "Primary public IPv4 address of the VPS (used for DNS A records). Source: Bitwarden rodrigo-agent/domain-config"
  type        = string

  validation {
    condition     = can(regex("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", var.vps_ip))
    error_message = "vps_ip must be a valid IPv4 address."
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Connection metadata (used by deploy scripts)
***REMOVED*** -----------------------------------------------------------------------------

variable "ssh_user" {
  description = "SSH user for the VPS (used by deploy scripts). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = length(var.ssh_user) > 0
    error_message = "ssh_user must not be empty."
  }
}

variable "ssh_port" {
  description = "SSH port for the VPS (used by deploy scripts). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = number

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1 and 65535."
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Object Storage Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "state_bucket_name" {
  description = "S3 bucket name for OpenTofu remote state. Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.state_bucket_name))
    error_message = "State bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "backup_bucket_name" {
  description = "S3 bucket name for restic backups. Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.backup_bucket_name))
    error_message = "Backup bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_region" {
  description = "S3-compatible Object Storage region identifier (e.g. gra, sbg). Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.storage_region))
    error_message = "Storage region must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_endpoint" {
  description = "S3-compatible Object Storage HTTPS endpoint URL. Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+$", var.storage_endpoint))
    error_message = "Storage endpoint must be an HTTPS URL with lowercase letters, digits, dots, and hyphens."
  }
}

variable "storage_access_key" {
  description = "Access key for S3-compatible Object Storage. Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.storage_access_key) > 0
    error_message = "storage_access_key must not be empty."
  }
}

variable "storage_secret_key" {
  description = "Secret key for S3-compatible Object Storage. Source: Bitwarden rodrigo-agent/tofu-inputs"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.storage_secret_key) > 0
    error_message = "storage_secret_key must not be empty."
  }
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Lambda Cloud (OCR GPU Instance)
***REMOVED*** -----------------------------------------------------------------------------

variable "ocr_enabled" {
  description = "Enable the OCR GPU instance in Tofu (set to true when OCR is needed)"
  type        = bool
  default     = false
}

variable "ocr_instance_name" {
  description = "Name for the Lambda GPU instance running Unlimited-OCR"
  type        = string
  default     = "unlimited-ocr"
}

variable "ocr_instance_type" {
  description = "Lambda GPU instance type (gpu_1x_a10=24GB, gpu_1x_l40s=48GB, gpu_1x_a100_sxm4=40GB)"
  type        = string
  default     = "gpu_1x_a10"
}

variable "ocr_region" {
  description = "Lambda region to launch the OCR instance"
  type        = string
  default     = "us-west-2"
}

variable "lambda_ssh_public_key" {
  description = "SSH public key to register with Lambda Cloud for OCR instance access"
  type        = string
  sensitive   = true
  default     = ""
}
