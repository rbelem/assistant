***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Outputs — Key infrastructure values
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** These values are displayed after `tofu apply` and can be referenced by
***REMOVED*** other configurations or scripts.
***REMOVED*** -----------------------------------------------------------------------------

output "vps_service_name" {
  description = "OVH internal service name for the VPS (used for API calls and import)"
  value       = ovh_vps.agent.service_name
}

output "vps_display_name" {
  description = "Display name of the VPS in OVH Manager"
  value       = ovh_vps.agent.display_name
}

output "vps_zone" {
  description = "OVH zone/region where the VPS is located"
  value       = ovh_vps.agent.zone
}

output "vps_state" {
  description = "Current state of the VPS (running, stopped, installing, etc.)"
  value       = ovh_vps.agent.state
}

output "vps_model" {
  description = "VPS model details (vCPU, RAM, disk)"
  value       = ovh_vps.agent.model
}

output "vps_ip" {
  description = "Primary public IP address of the VPS"
  value       = data.ovh_vps.agent_details.ips[0]
}

output "vps_ips" {
  description = "All IP addresses attached to the VPS"
  value       = data.ovh_vps.agent_details.ips
}

output "dns_fqdn" {
  description = "Base domain name (REDACTED-DOMAIN)"
  value       = var.domain_name
}

output "state_bucket" {
  description = "S3 bucket name for OpenTofu remote state"
  value       = aws_s3_bucket.tofu_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the state bucket"
  value       = aws_s3_bucket.tofu_state.arn
}

output "backup_bucket" {
  description = "S3 bucket name for restic backups"
  value       = aws_s3_bucket.backups.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the backup bucket"
  value       = aws_s3_bucket.backups.arn
}

output "storage_endpoint" {
  description = "OVH S3-compatible Object Storage endpoint URL"
  value       = "https://s3.${var.storage_region}.io.REDACTED-OVH-DOMAIN"
}

output "ssh_command" {
  description = "SSH command to connect to the VPS (after nixos-infect, use root@)"
  value       = "ssh root@hermes.${var.domain_name}"
}

output "ovh_subsidiary" {
  description = "OVH subsidiary used for billing"
  value       = data.ovh_me.account.ovh_subsidiary
}

***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Lambda Cloud (OCR)
***REMOVED*** -----------------------------------------------------------------------------

output "ocr_instance_ip" {
  description = "Public IP of the Lambda OCR GPU instance"
  value       = var.ocr_enabled ? try(data.lambda_instance.ocr_running[0].ip, "") : ""
}

output "ocr_instance_status" {
  description = "Status of the OCR GPU instance"
  value       = var.ocr_enabled ? try(data.lambda_instance.ocr_running[0].status, "") : ""
}

output "ocr_instance_type" {
  description = "GPU instance type for OCR"
  value       = var.ocr_instance_type
}

output "ocr_api_endpoint" {
  description = "OpenAI-compatible API endpoint for the OCR model"
  value       = var.ocr_enabled ? "http://${try(data.lambda_instance.ocr_running[0].ip, "")}:10000/v1" : ""
}
