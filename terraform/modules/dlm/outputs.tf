output "policy_id" {
  description = "ID of the DLM lifecycle policy"
  value       = var.enabled ? aws_dlm_lifecycle_policy.this[0].id : null
}

output "policy_arn" {
  description = "ARN of the DLM lifecycle policy"
  value       = var.enabled ? aws_dlm_lifecycle_policy.this[0].arn : null
}

output "policy_tags" {
  description = "Tags applied to the DLM lifecycle policy"
  value       = var.enabled ? aws_dlm_lifecycle_policy.this[0].tags_all : null
}