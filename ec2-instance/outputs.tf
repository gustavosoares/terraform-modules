output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Security group ID of the instance"
  value       = aws_security_group.this.id
}

output "iam_role_name" {
  description = "IAM role name attached to the instance"
  value       = aws_iam_role.this.name
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the instance"
  value       = aws_iam_role.this.arn
}

output "instance_arn" {
  description = "EC2 instance ARN"
  value       = aws_instance.this.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile attached to the instance"
  value       = aws_iam_instance_profile.this.name
}

output "ami_id" {
  description = "AMI the instance was launched from (useful when the latest Amazon Linux 2023 AMI was looked up)"
  value       = aws_instance.this.ami
}
