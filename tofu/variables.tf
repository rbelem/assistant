***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Input Variables — Hetzner Cloud VPS + Infrastructure Configuration
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Values are sourced from Bitwarden via scripts/fetch_vault.sh, which renders:
***REMOVED***   .rendered/terraform.tfvars   (tfvars passed via tofu-wrapper.sh)
***REMOVED***   .rendered/vault.env          (TF_VAR_* env vars)
***REMOVED*** No environment-specific defaults are committed in this public repo.
***REMOVED*** -----------------------------------------------------------------------------

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Hetzner Cloud Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "hcloud_token" {
  description = "Hetzner Cloud API token. Source: Bitwarden assistant/tofu-inputs (hcloud_token key)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.hcloud_token) > 0
    error_message = "hcloud_token must not be empty."
  }
}

variable "hcloud_server_type" {
  description = "Hetzner Cloud server type. CX33 = 8 vCPU / 16 GB / 160 GB / ~€34/mo. Source: Bitwarden assistant/tofu-inputs"
  type        = string
  default     = "cx33"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.hcloud_server_type))
    error_message = "Server type must be lowercase letters, digits, and hyphens."
  }
}

variable "hcloud_location" {
  description = "Hetzner Cloud location. hel1 = Helsinki, Finland. (fsn1 Falkenstein, nbg1 Nuremberg, ash/hil US also available)"
  type        = string
  default     = "hel1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.hcloud_location))
    error_message = "Location must be lowercase letters, digits, and hyphens."
  }
}

variable "hcloud_image" {
  description = "Image name or numeric ID. Ubuntu 26.04 (because Hetzner has no native NixOS). nixos-infect runs after first boot via Ansible"
  type        = string
  default     = "ubuntu-26.04"
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** VPS Configuration
***REMOVED*** -----------------------------------------------------------------------------

variable "vps_display_name" {
  description = "Display name for the VPS in Hetzner Cloud console. Source: Bitwarden assistant/tofu-inputs"
  type        = string

  validation {
    condition     = length(var.vps_display_name) > 0
    error_message = "VPS display name must not be empty."
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

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** DNS Configuration
***REMOVED*** -----------------------------------------------------------------------------

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

variable "porkbun_api_key" {
  description = "Porkbun API key. Source: Bitwarden assistant/Porkbun API Key (field api_key)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.porkbun_api_key) > 0
    error_message = "porkbun_api_key must not be empty."
  }
}

variable "porkbun_secret_api_key" {
  description = "Porkbun secret API key. Source: Bitwarden assistant/Porkbun API Key (field secret_api_key)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.porkbun_secret_api_key) > 0
    error_message = "porkbun_secret_api_key must not be empty."
  }
}

***REMOVED*** vps_ip removed (unused — DNS A records use hcloud_server.agent.ipv4_address output).
***REMOVED*** Previously validated as IPv4 which blocked first deploy when VPS didn't exist yet.

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Connection metadata (used by deploy scripts)
***REMOVED*** -----------------------------------------------------------------------------

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

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Object Storage Configuration
***REMOVED*** -----------------------------------------------------------------------------

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
