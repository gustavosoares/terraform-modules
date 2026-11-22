resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_id
  tags              = var.tags
}

resource "aws_cloudwatch_log_subscription_filter" "this" {
  count = var.log_subscription != null ? 1 : 0

  name            = "${var.name}-logs"
  log_group_name  = aws_cloudwatch_log_group.this.name
  destination_arn = var.log_subscription.destination_arn
  role_arn        = var.log_subscription.role_arn
  filter_pattern  = var.log_subscription.filter_pattern
}
