# -----------------------------------------------------------------------------
# Input Variables — Hostinger VPS + Infrastructure Configuration
# -----------------------------------------------------------------------------
# Values are sourced from Bitwarden via scripts/fetch_vault.sh, which renders:
#   .rendered/terraform.tfvars   (tfvars passed via tofu-wrapper.sh)
#   .rendered/vault.env          (TF_VAR_* env vars)
# No environment-specific defaults are committed in this public repo.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Hostinger API Configuration
# -----------------------------------------------------------------------------

variable "hostinger_api_token" {
  description = "Hostinger API token for VPS provisioning. Source: Bitwarden assistant/tofu-inputs"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.hostinger_api_token) > 0
    error_message = "hostinger_api_token must not be empty."
  }
}

# -----------------------------------------------------------------------------
# VPS Configuration
# -----------------------------------------------------------------------------

variable "vps_display_name" {
  description = "Display name for the VPS in Hostinger control panel. Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = length(var.vps_display_name) > 0
    error_message = "VPS display name must not be empty."
  }
}

variable "hostinger_vps_plan" {
  description = "Hostinger VPS plan code (e.g. hostingercom-vps-kvm4-2-4). Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+$", var.hostinger_vps_plan))
    error_message = "VPS plan code must be lowercase letters, digits, and hyphens."
  }
}

variable "hostinger_data_center_id" {
  description = "Hostinger data center ID (numeric). Source: Bitwarden assistant/tofu-inputs"
  type        = number

  validation {
    condition     = var.hostinger_data_center_id > 0
    error_message = "Data center ID must be a positive integer."
  }
}

variable "hostinger_template_id" {
  description = "Hostinger OS template ID (numeric, e.g. NixOS template). Source: Bitwarden assistant/tofu-inputs"
  type        = number

  validation {
    condition     = var.hostinger_template_id > 0
    error_message = "Template ID must be a positive integer."
  }
}

variable "ssh_public_key" {
  description = "SSH public key to pre-install on the VPS (full key string, e.g. 'ssh-ed25519 AAAA...'). Source: Bitwarden assistant/tofu-inputs"
  type        = string
  sensitive   = true

  validation {
    condition     = var.ssh_public_key == "" || can(regex("^ssh-(rsa|ed25519|dss|ecdsa) ", var.ssh_public_key))
    error_message = "SSH public key must be empty or a valid ssh-rsa/ed25519/dss/ecdsa public key."
  }
}

# -----------------------------------------------------------------------------
# DNS Configuration
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Base domain name (managed by Porkbun DNS). Source: Bitwarden assistant/domain-config"
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
  description = "Subdomain list (per-service A records). Source: Bitwarden assistant/domain-config"

  validation {
    condition     = length(var.subdomains) > 0 && alltrue([for s in var.subdomains : length(s) > 0 && !can(regex("\\.", s))])
    error_message = "subdomains must be a non-empty list of single-label hostnames (no dots)."
  }
}

variable "vps_ip" {
  description = "Primary public IPv4 address of the VPS (used for DNS A records). Source: Bitwarden assistant/domain-config"
  type        = string

  validation {
    condition     = can(regex("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", var.vps_ip))
    error_message = "vps_ip must be a valid IPv4 address."
  }
}

# -----------------------------------------------------------------------------
# Connection metadata (used by deploy scripts)
# -----------------------------------------------------------------------------

variable "ssh_user" {
  description = "SSH user for the VPS (used by deploy scripts). Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = length(var.ssh_user) > 0
    error_message = "ssh_user must not be empty."
  }
}

variable "ssh_port" {
  description = "SSH port for the VPS (used by deploy scripts). Source: Bitwarden assistant/tofu-inputs"
  type        = number

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Object Storage Configuration
# -----------------------------------------------------------------------------

variable "state_bucket_name" {
  description = "S3 bucket name for OpenTofu remote state. Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.state_bucket_name))
    error_message = "State bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "backup_bucket_name" {
  description = "S3 bucket name for restic backups. Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.backup_bucket_name))
    error_message = "Backup bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_region" {
  description = "S3-compatible Object Storage region identifier (e.g. eu-central-1). Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.storage_region))
    error_message = "Storage region must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_endpoint" {
  description = "S3-compatible Object Storage HTTPS endpoint URL. Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+$", var.storage_endpoint))
    error_message = "Storage endpoint must be an HTTPS URL with lowercase letters, digits, dots, and hyphens."
  }
}

variable "storage_access_key" {
  description = "Access key for S3-compatible Object Storage. Source: Bitwarden assistant/tofu-inputs"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.storage_access_key) > 0
    error_message = "storage_access_key must not be empty."
  }
}

variable "storage_secret_key" {
  description = "Secret key for S3-compatible Object Storage. Source: Bitwarden assistant/tofu-inputs"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.storage_secret_key) > 0
    error_message = "storage_secret_key must not be empty."
  }
}

# -----------------------------------------------------------------------------
# Lambda Cloud (OCR GPU Instance)
# -----------------------------------------------------------------------------

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
