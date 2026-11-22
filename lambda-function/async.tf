locals {
  create_dlq = try(var.async_config.create_dead_letter_queue, false)
}

resource "aws_sqs_queue" "dead_letter" {
  count = local.create_dlq ? 1 : 0

  name                      = "${var.name}-async-dlq"
  message_retention_seconds = var.async_config.dead_letter_queue_retention_seconds
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

data "aws_iam_policy_document" "dead_letter" {
  count = local.create_dlq ? 1 : 0

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dead_letter[0].arn]
  }
}

resource "aws_iam_role_policy" "dead_letter" {
  count = local.create_dlq ? 1 : 0

  name   = "async-dead-letter-queue"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.dead_letter[0].json
}

resource "aws_lambda_function_event_invoke_config" "this" {
  count = var.async_config != null ? 1 : 0

  function_name                = local.function.function_name
  maximum_retry_attempts       = var.async_config.maximum_retry_attempts
  maximum_event_age_in_seconds = var.async_config.maximum_event_age_in_seconds

  dynamic "destination_config" {
    for_each = local.create_dlq ? [1] : []
    content {
      on_failure {
        destination = aws_sqs_queue.dead_letter[0].arn
      }
    }
  }

  depends_on = [aws_iam_role_policy.dead_letter]
}
