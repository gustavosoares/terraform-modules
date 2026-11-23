data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  tags = var.tags
}

################################################################################
# Lifecycle policy
################################################################################

locals {
  lifecycle_rules = concat(
    var.untagged_image_expiration_days != null ? [{
      description = "Expire untagged images after ${var.untagged_image_expiration_days} days"
      tagStatus   = "untagged"
      countType   = "sinceImagePushed"
      countUnit   = "days"
      countNumber = var.untagged_image_expiration_days
    }] : [],
    var.max_image_count != null ? [{
      description = "Keep the ${var.max_image_count} most recent images"
      tagStatus   = "any"
      countType   = "imageCountMoreThan"
      countUnit   = null
      countNumber = var.max_image_count
    }] : [],
  )
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = length(local.lifecycle_rules) > 0 ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [
      for i, rule in local.lifecycle_rules : {
        rulePriority = i + 1
        description  = rule.description
        selection = { for k, v in {
          tagStatus   = rule.tagStatus
          countType   = rule.countType
          countUnit   = rule.countUnit
          countNumber = rule.countNumber
        } : k => v if v != null }
        action = { type = "expire" }
      }
    ]
  })
}

################################################################################
# Repository policy
################################################################################

locals {
  lambda_account_ids = distinct(concat([data.aws_caller_identity.current.account_id], var.pull_account_ids))
  pull_actions       = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
  create_policy      = length(var.pull_account_ids) > 0 || var.enable_lambda_pull
}

data "aws_iam_policy_document" "this" {
  count = local.create_policy ? 1 : 0

  dynamic "statement" {
    for_each = length(var.pull_account_ids) > 0 ? [1] : []
    content {
      sid     = "CrossAccountPull"
      actions = concat(local.pull_actions, ["ecr:BatchCheckLayerAvailability"])

      principals {
        type        = "AWS"
        identifiers = [for id in var.pull_account_ids : "arn:${data.aws_partition.current.partition}:iam::${id}:root"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_lambda_pull ? [1] : []
    content {
      sid     = "LambdaPull"
      actions = local.pull_actions

      principals {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "aws:sourceArn"
        values   = [for id in local.lambda_account_ids : "arn:${data.aws_partition.current.partition}:lambda:*:${id}:function:*"]
      }
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  count = local.create_policy ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.this[0].json
}
