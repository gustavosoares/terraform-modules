output "name" {
  description = "Name (ID) of the bucket"
  value       = aws_s3_bucket.s3_bucket.id
}

output "arn" {
  description = "ARN of the bucket"
  value       = aws_s3_bucket.s3_bucket.arn
}

output "regional_domain_name" {
  description = "Region-specific domain name of the bucket (e.g. for CloudFront origins)"
  value       = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the bucket (module-created or custom); null when SSE-KMS is disabled."
  value       = var.kms_encryption_enabled ? local.kms_key : null
}

output "kms_key_id" {
  description = "ID of the module-created KMS key; null when encryption is disabled or a custom key is used."
  value       = try(aws_kms_key.s3_bucket_key[0].id, null)
}

# =============================================================================
# IRSA (IAM Roles for Service Accounts) - EKS pod access
# =============================================================================

output "irsa_role_arn" {
  description = "ARN of the IRSA IAM role. Annotate the pod ServiceAccount with eks.amazonaws.com/role-arn set to this value. Null when create_irsa_role is false."
  value       = var.create_irsa_role ? aws_iam_role.irsa_s3_access[0].arn : null
}

output "irsa_policy_arn" {
  description = "ARN of the IAM policy granting bucket access. Null when create_irsa_role is false."
  value       = var.create_irsa_role ? aws_iam_policy.irsa_s3_access[0].arn : null
}
