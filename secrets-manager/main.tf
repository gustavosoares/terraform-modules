resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region     = replica.value.region
      kms_key_id = replica.value.kms_key_id
    }
  }

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "initial" {
  count = var.initial_secret_string != null ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.initial_secret_string

  # Only the first value comes from Terraform; rotation or manual updates win afterwards.
  lifecycle {
    ignore_changes = [secret_string]
  }
}

################################################################################
# Resource policy
################################################################################

data "aws_iam_policy_document" "resource" {
  count = length(var.read_principal_arns) > 0 ? 1 : 0

  statement {
    sid       = "Read"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = var.read_principal_arns
    }
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = length(var.read_principal_arns) > 0 ? 1 : 0

  secret_arn          = aws_secretsmanager_secret.this.arn
  policy              = data.aws_iam_policy_document.resource[0].json
  block_public_policy = true
}

################################################################################
# Identity policy for readers (output only)
################################################################################

data "aws_iam_policy_document" "read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.this.arn]
  }

  dynamic "statement" {
    for_each = var.kms_key_id != null && startswith(coalesce(var.kms_key_id, "-"), "arn:") ? [1] : []
    content {
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_id]
    }
  }
}
