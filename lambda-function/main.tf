data "aws_partition" "current" {}

locals {
  is_image = var.image_uri != null
  use_stub = var.filename == null && var.s3_source == null && var.image_uri == null

  filename = local.use_stub ? data.archive_file.stub[0].output_path : var.filename

  source_code_hash = (
    var.source_code_hash != null ? var.source_code_hash :
    local.use_stub ? data.archive_file.stub[0].output_base64sha256 :
    var.filename != null ? filebase64sha256(var.filename) :
    null
  )

  security_group_ids = var.network_config == null ? [] : concat(
    [aws_security_group.this[0].id],
    var.network_config.additional_security_group_ids,
  )

  # Exactly one of the two function resources exists; everything else refers to this.
  function = one(concat(aws_lambda_function.this, aws_lambda_function.ignore_code))
}

# Placeholder code, deployed when no package is given (typically with
# ignore_code_changes = true, where CI deploys the real code later). The zip holds
# a Node.js and a Python handler so the default handler works for either runtime.
data "archive_file" "stub" {
  count = local.use_stub ? 1 : 0

  type        = "zip"
  output_path = "${path.root}/.terraform/lambda-function-stubs/${var.name}.zip"

  source {
    filename = "index.js"
    content  = "exports.handler = async () => ({ statusCode: 200, body: \"stub\" });\n"
  }

  source {
    filename = "index.py"
    content  = "def handler(event, context):\n    return {\"statusCode\": 200, \"body\": \"stub\"}\n"
  }
}

# The two resources below must stay identical apart from count and lifecycle.

resource "aws_lambda_function" "this" {
  count = var.ignore_code_changes ? 0 : 1

  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn

  package_type      = local.is_image ? "Image" : "Zip"
  image_uri         = var.image_uri
  filename          = local.filename
  s3_bucket         = try(var.s3_source.bucket, null)
  s3_key            = try(var.s3_source.key, null)
  s3_object_version = try(var.s3_source.object_version, null)
  source_code_hash  = local.source_code_hash
  handler           = local.is_image ? null : var.handler
  runtime           = local.is_image ? null : var.runtime
  layers            = var.layers

  architectures                  = var.architectures
  memory_size                    = var.memory_size
  timeout                        = var.timeout
  reserved_concurrent_executions = var.reserved_concurrent_executions

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = var.network_config != null ? [1] : []
    content {
      subnet_ids         = var.network_config.subnet_ids
      security_group_ids = local.security_group_ids
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.logs,
    aws_iam_role_policy_attachment.vpc_access,
  ]

  lifecycle {
    precondition {
      condition     = length(compact([var.filename, try(var.s3_source.key, null), var.image_uri])) <= 1
      error_message = "Set at most one of filename, s3_source or image_uri."
    }
  }
}

resource "aws_lambda_function" "ignore_code" {
  count = var.ignore_code_changes ? 1 : 0

  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn

  package_type      = local.is_image ? "Image" : "Zip"
  image_uri         = var.image_uri
  filename          = local.filename
  s3_bucket         = try(var.s3_source.bucket, null)
  s3_key            = try(var.s3_source.key, null)
  s3_object_version = try(var.s3_source.object_version, null)
  source_code_hash  = local.source_code_hash
  handler           = local.is_image ? null : var.handler
  runtime           = local.is_image ? null : var.runtime
  layers            = var.layers

  architectures                  = var.architectures
  memory_size                    = var.memory_size
  timeout                        = var.timeout
  reserved_concurrent_executions = var.reserved_concurrent_executions

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = var.network_config != null ? [1] : []
    content {
      subnet_ids         = var.network_config.subnet_ids
      security_group_ids = local.security_group_ids
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.logs,
    aws_iam_role_policy_attachment.vpc_access,
  ]

  lifecycle {
    precondition {
      condition     = length(compact([var.filename, try(var.s3_source.key, null), var.image_uri])) <= 1
      error_message = "Set at most one of filename, s3_source or image_uri."
    }

    ignore_changes = [
      filename,
      s3_bucket,
      s3_key,
      s3_object_version,
      image_uri,
      source_code_hash,
    ]
  }
}
