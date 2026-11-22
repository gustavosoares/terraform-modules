output "repository_arn" {
  description = "Repository ARN"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Repository name"
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "Repository URL, e.g. 111111111111.dkr.ecr.us-east-1.amazonaws.com/my-app"
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "Registry (account) ID that owns the repository"
  value       = aws_ecr_repository.this.registry_id
}
