output "resource_prefix" {
  description = "Naming prefix used for all resources (asg-<name>-<environment>). Useful for naming related resources such as load balancers."
  value       = local.resource_prefix
}

output "asg_id" {
  description = "The Auto Scaling Group ID"
  value       = aws_autoscaling_group.this.id
}

output "asg_name" {
  description = "The Auto Scaling Group name"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "The Auto Scaling Group ARN"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "The Launch Template ID"
  value       = aws_launch_template.this.id
}

output "launch_template_arn" {
  description = "The Launch Template ARN"
  value       = aws_launch_template.this.arn
}

output "launch_template_latest_version" {
  description = "The latest version of the Launch Template"
  value       = aws_launch_template.this.latest_version
}

output "security_group_id" {
  description = "The security group ID (if created)"
  value       = var.security_group_config.create ? aws_security_group.this[0].id : null
}

output "security_group_arn" {
  description = "The security group ARN (if created)"
  value       = var.security_group_config.create ? aws_security_group.this[0].arn : null
}

output "iam_role_id" {
  description = "The IAM role ID (if created)"
  value       = var.iam_config.create_role ? aws_iam_role.this[0].id : null
}

output "iam_role_arn" {
  description = "The IAM role ARN (if created)"
  value       = var.iam_config.create_role ? aws_iam_role.this[0].arn : null
}

output "iam_role_name" {
  description = "The IAM role name (if created)"
  value       = var.iam_config.create_role ? aws_iam_role.this[0].name : null
}

output "iam_instance_profile_id" {
  description = "The IAM instance profile ID (if created)"
  value       = var.iam_config.create_instance_profile ? aws_iam_instance_profile.this[0].id : null
}

output "iam_instance_profile_arn" {
  description = "The IAM instance profile ARN (if created)"
  value       = var.iam_config.create_instance_profile ? aws_iam_instance_profile.this[0].arn : null
}

output "iam_instance_profile_name" {
  description = "The IAM instance profile name used by instances (created or existing); null if none"
  value       = local.instance_profile_name
}

output "scaling_policy_arns" {
  description = "Map of scaling policy names to ARNs"
  value = {
    for name, policy in aws_autoscaling_policy.this : name => policy.arn
  }
}

output "persistent_volume_ids" {
  description = "Map of persistent volume names to volume IDs"
  value = {
    for name, vol in aws_ebs_volume.persistent : name => vol.id
  }
}

output "persistent_volume_arns" {
  description = "Map of persistent volume names to volume ARNs"
  value = {
    for name, vol in aws_ebs_volume.persistent : name => vol.arn
  }
}
