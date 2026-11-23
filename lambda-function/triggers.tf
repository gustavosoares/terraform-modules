################################################################################
# SQS
################################################################################

data "aws_iam_policy_document" "sqs" {
  count = var.sqs_trigger != null ? 1 : 0

  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.sqs_trigger.queue_arn]
  }

  dynamic "statement" {
    for_each = var.sqs_trigger.kms_key_arn != null ? [1] : []
    content {
      actions   = ["kms:Decrypt"]
      resources = [var.sqs_trigger.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "sqs" {
  count = var.sqs_trigger != null ? 1 : 0

  name   = "sqs-trigger"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.sqs[0].json
}

resource "aws_lambda_event_source_mapping" "sqs" {
  count = var.sqs_trigger != null ? 1 : 0

  function_name                      = local.function.arn
  event_source_arn                   = var.sqs_trigger.queue_arn
  batch_size                         = var.sqs_trigger.batch_size
  maximum_batching_window_in_seconds = var.sqs_trigger.maximum_batching_window_in_seconds
  enabled                            = var.sqs_trigger.enabled
  function_response_types            = var.sqs_trigger.report_batch_item_failures ? ["ReportBatchItemFailures"] : null
  tags                               = var.tags

  # The mapping validates the role's queue permissions on create.
  depends_on = [aws_iam_role_policy.sqs]
}

################################################################################
# Schedule
################################################################################

resource "aws_cloudwatch_event_rule" "schedule" {
  count = var.schedule != null ? 1 : 0

  name                = "${var.name}-schedule"
  description         = coalesce(var.schedule.description, "Schedule for ${var.name}")
  schedule_expression = var.schedule.expression
  state               = var.schedule.enabled ? "ENABLED" : "DISABLED"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  count = var.schedule != null ? 1 : 0

  rule  = aws_cloudwatch_event_rule.schedule[0].name
  arn   = local.function.arn
  input = var.schedule.input
}

resource "aws_lambda_permission" "schedule" {
  count = var.schedule != null ? 1 : 0

  statement_id  = "AllowEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = local.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[0].arn
}
