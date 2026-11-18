# =============================================================================
# VPC Flow Logs (optional)
# =============================================================================
# When do_flow_logs = true, flow logs are delivered to S3. Either pass an
# existing bucket ARN via flow_logs_destination_arn, or let the module create
# a dedicated bucket.

locals {
  create_flow_logs_bucket = var.do_flow_logs && var.flow_logs_destination_arn == null
  flow_logs_bucket_name   = "${var.name_prefix}-vpc-flow-logs-${local.aws_account_id}"
  flow_logs_destination   = local.create_flow_logs_bucket ? aws_s3_bucket.flow_logs[0].arn : var.flow_logs_destination_arn
}

resource "aws_flow_log" "main" {
  count = var.do_flow_logs ? 1 : 0

  log_destination      = local.flow_logs_destination
  log_destination_type = "s3"
  traffic_type         = var.flow_logs_traffic_type
  vpc_id               = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc-flow-logs"
  })

  depends_on = [aws_s3_bucket_policy.flow_logs]
}

# =============================================================================
# Flow Logs S3 Bucket (created only when no destination ARN is provided)
# =============================================================================

resource "aws_s3_bucket" "flow_logs" {
  count = local.create_flow_logs_bucket ? 1 : 0

  bucket        = local.flow_logs_bucket_name
  force_destroy = var.flow_logs_bucket_force_destroy

  tags = merge(var.tags, {
    Name = local.flow_logs_bucket_name
  })
}

resource "aws_s3_bucket_ownership_controls" "flow_logs" {
  count = local.create_flow_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = local.create_flow_logs_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = local.create_flow_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = local.create_flow_logs_bucket && var.flow_logs_retention_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.flow_logs_retention_days
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = local.create_flow_logs_bucket ? 1 : 0

  statement {
    sid       = "AWSLogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${local.aws_account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.aws_account_id]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.flow_logs[0].arn]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.aws_account_id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.flow_logs[0].arn, "${aws_s3_bucket.flow_logs[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  count = local.create_flow_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}
