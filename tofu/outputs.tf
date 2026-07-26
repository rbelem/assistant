***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** Outputs — Key infrastructure values
***REMOVED*** -----------------------------------------------------------------------------
***REMOVED*** These values are displayed after `tofu apply` and can be referenced by
***REMOVED*** other configurations or scripts.
***REMOVED*** -----------------------------------------------------------------------------

output "vps_id" {
  description = "Hostinger VPS ID"
  value       = hostinger_vps.agent.id
}

output "vps_name" {
  description = "Display name of the VPS"
  value       = hostinger_vps.agent.name
}

output "vps_ip" {
  description = "Primary public IPv4 address of the VPS"
  value       = hostinger_vps.agent.ipv4
}

output "vps_ipv6" {
  description = "Primary public IPv6 address of the VPS"
  value       = hostinger_vps.agent.ipv6
}

output "vps_status" {
  description = "Current status of the VPS"
  value       = hostinger_vps.agent.status
}

output "dns_fqdn" {
  description = "Base domain name"
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
  description = "S3-compatible Object Storage endpoint URL (sourced from vault)"
  value       = var.storage_endpoint
}

output "ssh_command" {
  description = "SSH command to access the provisioned VPS"
  value       = "ssh -p ${var.ssh_port} ${var.ssh_user}@${hostinger_vps.agent.ipv4}"
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
