data "aws_caller_identity" "current" {}

locals {
  aws_account_id = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)

  generated_bucket_name = join("-", compact([var.bucket_name_prefix, var.name, var.environment]))
  bucket_name           = coalesce(var.custom_bucket_name, local.generated_bucket_name)

  base_account_root     = "arn:aws:iam::${local.aws_account_id}:root"
  kms_policy_principals = [local.base_account_root]
  kms_key               = var.use_custom_kms_key ? var.kms_key_arn : join("", aws_kms_key.s3_bucket_key[*].arn)

  # IRSA: restrict to one service account, or allow any SA in k8s_namespace
  irsa_oidc_sub = var.irsa_service_account_name != "" ? "system:serviceaccount:${var.k8s_namespace}:${var.irsa_service_account_name}" : "system:serviceaccount:${var.k8s_namespace}:*"
}

resource "aws_s3_bucket" "s3_bucket" {
  bucket = local.bucket_name

  tags = var.tags
}

data "aws_iam_policy_document" "kms_bucket_policy" {
  version = "2012-10-17"

  lifecycle {
    precondition {
      condition     = length(var.kms_external_encryption_account_ids) == 0 || var.kms_external_use_root_account || var.kms_external_role_name != null
      error_message = "kms_external_role_name must be set when kms_external_encryption_account_ids is non-empty and kms_external_use_root_account is false."
    }
  }

  statement {
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = local.kms_policy_principals
    }
    resources = ["*"]
  }
  dynamic "statement" {
    for_each = length(var.kms_external_encryption_account_ids) > 0 ? [1] : []

    content {
      effect = "Allow"

      actions = var.kms_external_allow_decrypt ? [
        "kms:GenerateDataKey",
        "kms:Decrypt",
        "kms:DescribeKey"
        ] : [
        "kms:GenerateDataKey"
      ]

      principals {
        type        = "AWS"
        identifiers = var.kms_external_use_root_account ? [for account_id in var.kms_external_encryption_account_ids : "arn:aws:iam::${account_id}:root"] : [for account_id in var.kms_external_encryption_account_ids : "arn:aws:iam::${account_id}:role/${var.kms_external_role_name}"]
      }

      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_oac_distribution_arns) > 0 ? [1] : []

    content {
      sid    = "AllowCloudFrontServicePrincipalSSE-KMS"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey*"
      ]
      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = var.cloudfront_oac_distribution_arns
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls       = var.disable_acls ? true : var.block_public_acls
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = var.restrict_public_buckets
}

resource "aws_kms_key" "s3_bucket_key" {
  count = var.kms_encryption_enabled && !var.use_custom_kms_key ? 1 : 0

  description             = "${var.name}-${var.environment}-key"
  deletion_window_in_days = 14
  # When manage_kms_key_policy is false, a parent module owns the key policy (e.g. via aws_kms_key_policy).
  policy              = var.manage_kms_key_policy ? data.aws_iam_policy_document.kms_bucket_policy.json : null
  enable_key_rotation = true

  tags = var.tags
}

resource "aws_kms_alias" "s3_bucket_key_alias" {
  count = var.kms_encryption_enabled && !var.use_custom_kms_key ? 1 : 0

  name          = "alias/${var.name}-${var.environment}-bucket-key"
  target_key_id = aws_kms_key.s3_bucket_key[count.index].arn
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    # S3 has no "Disabled" state once versioning has been enabled; "Suspended" is the off state.
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_logging" "access_logging" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket.id

  target_bucket = var.access_logging_destination_bucket_name
  target_prefix = coalesce(var.access_logging_target_prefix, "${aws_s3_bucket.s3_bucket.id}/")

  lifecycle {
    precondition {
      condition     = var.access_logging_destination_bucket_name != null && var.access_logging_destination_bucket_name != ""
      error_message = "access_logging_destination_bucket_name must be set when enable_access_logging is true."
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption_config" {
  count  = var.kms_encryption_enabled || var.aes256_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket.bucket

  rule {
    # AWS returns blocked_encryption_types = ["NONE"] on read for default bucket encryption
    # controls; [] or omitting this attribute causes a perpetual replace of the rule on every plan.
    blocked_encryption_types = ["NONE"]
    bucket_key_enabled       = false

    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_encryption_enabled ? local.kms_key : null
      sse_algorithm     = var.kms_encryption_enabled ? "aws:kms" : "AES256"
    }
  }
}

resource "aws_s3_bucket_notification" "event_bridge_notification" {
  count       = var.eventbridge_notifications ? 1 : 0
  bucket      = aws_s3_bucket.s3_bucket.bucket
  eventbridge = var.eventbridge_notifications
}

resource "aws_s3_bucket_cors_configuration" "cors" {
  count  = var.cors_configuration_enabled ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Apply the auto-delete lifecycle policy (only if at least one rule is enabled)
resource "aws_s3_bucket_lifecycle_configuration" "auto_delete_files_policy" {
  count = (var.auto_delete_files_rule_enabled || var.auto_delete_objects_rule_enabled) ? 1 : 0

  bucket = aws_s3_bucket.s3_bucket.id

  depends_on = [aws_s3_bucket_versioning.versioning]

  # Rule 1: Auto-delete ALL files after specified days
  dynamic "rule" {
    for_each = var.auto_delete_files_rule_enabled ? [1] : []
    content {
      id     = var.auto_delete_files_rule_id
      status = "Enabled"

      # Apply to all objects (required by AWS provider v6+)
      filter {}

      expiration {
        days = var.auto_delete_files_expiration_days
      }
    }
  }

  # Rule 2: Auto-delete only tagged objects after specified days
  dynamic "rule" {
    for_each = var.auto_delete_objects_rule_enabled ? [1] : []
    content {
      id = var.auto_delete_objects_rule_id

      filter {
        tag {
          key   = var.auto_delete_objects_rule_tag_key
          value = var.auto_delete_objects_rule_tag_value
        }
      }

      noncurrent_version_expiration {
        noncurrent_days = var.auto_delete_objects_rule_expiration_days
      }

      expiration {
        days = var.auto_delete_objects_rule_expiration_days
      }

      status = "Enabled"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "prefix_scoped" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket.id

  depends_on = [aws_s3_bucket_versioning.versioning]

  lifecycle {
    precondition {
      condition     = length(var.lifecycle_rules) == length(distinct([for r in var.lifecycle_rules : r.id]))
      error_message = "lifecycle_rules ids must be unique."
    }

    precondition {
      condition = alltrue([
        for r in var.lifecycle_rules :
        r.expiration_days != null || r.expired_object_delete_marker || r.noncurrent_expiration_days != null ||
        r.abort_incomplete_upload_days != null || length(r.transitions) > 0 || length(r.noncurrent_transitions) > 0
      ])
      error_message = "Each lifecycle rule must define at least one action: expiration_days, expired_object_delete_marker, noncurrent_expiration_days, abort_incomplete_upload_days, transitions, or noncurrent_transitions."
    }

    precondition {
      condition = alltrue([
        for r in var.lifecycle_rules : !(r.expiration_days != null && r.expired_object_delete_marker)
      ])
      error_message = "A lifecycle rule cannot set both expiration_days and expired_object_delete_marker; S3 rejects expiration blocks that combine them."
    }

    precondition {
      condition     = !(var.auto_delete_files_rule_enabled || var.auto_delete_objects_rule_enabled)
      error_message = "lifecycle_rules cannot be combined with auto_delete_files_rule_enabled/auto_delete_objects_rule_enabled; the module would create two lifecycle configurations for the same bucket and they would overwrite each other."
    }
  }

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null || rule.value.expired_object_delete_marker ? [1] : []
        content {
          days                         = rule.value.expiration_days
          expired_object_delete_marker = rule.value.expired_object_delete_marker ? true : null
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_expiration_days != null ? [rule.value.noncurrent_expiration_days] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_transitions
        content {
          noncurrent_days = noncurrent_version_transition.value.days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_upload_days != null ? [rule.value.abort_incomplete_upload_days] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "ownership" {
  count  = var.disable_acls || var.control_object_ownership ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket.id

  rule {
    object_ownership = var.disable_acls ? "BucketOwnerEnforced" : var.object_ownership
  }
}

# =============================================================================
# IRSA (IAM Roles for Service Accounts) - EKS pod access
# =============================================================================

data "aws_iam_policy_document" "irsa_s3_access" {
  count = var.create_irsa_role ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetObjectVersion"
    ]
    resources = [
      aws_s3_bucket.s3_bucket.arn,
      "${aws_s3_bucket.s3_bucket.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "irsa_s3_access" {
  count       = var.create_irsa_role ? 1 : 0
  name        = "${aws_s3_bucket.s3_bucket.id}-s3-access-policy"
  description = "IRSA policy for EKS pods to access S3 bucket ${var.name}"
  policy      = data.aws_iam_policy_document.irsa_s3_access[0].json
  tags        = var.tags
}

resource "aws_iam_role" "irsa_s3_access" {
  count = var.create_irsa_role ? 1 : 0
  name  = "${aws_s3_bucket.s3_bucket.id}-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringLike = {
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = local.irsa_oidc_sub
        }
      }
    }]
  })

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(var.oidc_provider_arn) > 0 && length(var.oidc_provider_url) > 0 && length(var.k8s_namespace) > 0
      error_message = "When create_irsa_role is true, oidc_provider_arn, oidc_provider_url, and k8s_namespace must be non-empty."
    }
  }
}

resource "aws_iam_role_policy_attachment" "irsa_s3_access" {
  count      = var.create_irsa_role ? 1 : 0
  role       = aws_iam_role.irsa_s3_access[0].name
  policy_arn = aws_iam_policy.irsa_s3_access[0].arn
}

# =============================================================================
# Bucket Policy
# =============================================================================

data "aws_iam_policy_document" "deny_insecure_transport" {
  count = var.attach_deny_insecure_transport_policy ? 1 : 0

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.s3_bucket.arn,
      "${aws_s3_bucket.s3_bucket.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "cloudfront_oac_bucket" {
  count = length(var.cloudfront_oac_distribution_arns) > 0 ? 1 : 0

  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.s3_bucket.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = var.cloudfront_oac_distribution_arns
    }
  }
}

data "aws_iam_policy_document" "combined_policy" {
  count = var.attach_policy || var.attach_deny_insecure_transport_policy || length(var.cloudfront_oac_distribution_arns) > 0 ? 1 : 0

  source_policy_documents = compact([
    var.attach_policy ? var.bucket_policy : null,
    var.attach_deny_insecure_transport_policy ? data.aws_iam_policy_document.deny_insecure_transport[0].json : null,
    length(var.cloudfront_oac_distribution_arns) > 0 ? data.aws_iam_policy_document.cloudfront_oac_bucket[0].json : null
  ])
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  count  = var.attach_policy || var.attach_deny_insecure_transport_policy || length(var.cloudfront_oac_distribution_arns) > 0 ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket.id
  policy = data.aws_iam_policy_document.combined_policy[0].json
}
