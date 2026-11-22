output "function_name" {
  description = "Lambda function name"
  value       = local.function.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = local.function.arn
}

output "qualified_arn" {
  description = "Lambda function ARN including the latest version"
  value       = local.function.qualified_arn
}

output "invoke_arn" {
  description = "ARN for invoking the function from API Gateway"
  value       = local.function.invoke_arn
}

output "version" {
  description = "Latest published version of the function"
  value       = local.function.version
}

output "role_arn" {
  description = "Function execution role ARN"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Function execution role name"
  value       = aws_iam_role.this.name
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = aws_cloudwatch_log_group.this.arn
}

output "security_group_id" {
  description = "Function security group ID, or null when not in a VPC"
  value       = try(aws_security_group.this[0].id, null)
}

output "dead_letter_queue_arn" {
  description = "Async dead-letter queue ARN, or null when not created"
  value       = try(aws_sqs_queue.dead_letter[0].arn, null)
}

output "dead_letter_queue_url" {
  description = "Async dead-letter queue URL, or null when not created"
  value       = try(aws_sqs_queue.dead_letter[0].url, null)
}

output "errors_alarm_arn" {
  description = "Errors alarm ARN, or null when not created"
  value       = try(aws_cloudwatch_metric_alarm.errors[0].arn, null)
}
