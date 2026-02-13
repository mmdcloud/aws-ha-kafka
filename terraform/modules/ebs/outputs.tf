output "volume_ids" {
  description = "Map of volume names to volume IDs"
  value       = { for k, v in aws_ebs_volume.this : k => v.id }
}

output "volume_arns" {
  description = "Map of volume names to volume ARNs"
  value       = { for k, v in aws_ebs_volume.this : k => v.arn }
}

output "volumes" {
  description = "Map of all volume attributes"
  value       = aws_ebs_volume.this
}

output "attachments" {
  description = "Map of all volume attachment attributes"
  value       = aws_volume_attachment.this
}