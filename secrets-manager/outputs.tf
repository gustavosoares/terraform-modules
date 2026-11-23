output "arn" {
  description = "Secret ARN"
  value       = aws_secretsmanager_secret.this.arn
}

output "id" {
  description = "Secret ID (same as the ARN)"
  value       = aws_secretsmanager_secret.this.id
}

output "name" {
  description = "Secret name"
  value       = aws_secretsmanager_secret.this.name
}

output "read_policy_json" {
  description = "IAM policy document granting read access to this secret (and kms:Decrypt on kms_key_id when it is an ARN), e.g. for a Lambda role"
  value       = data.aws_iam_policy_document.read.json
}
