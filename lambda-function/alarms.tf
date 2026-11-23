resource "aws_cloudwatch_metric_alarm" "errors" {
  count = var.errors_alarm != null ? 1 : 0

  alarm_name          = "${var.name}-errors"
  alarm_description   = "Lambda function ${var.name} reported ${var.errors_alarm.threshold} or more errors in ${var.errors_alarm.period}s"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = local.function.function_name }
  statistic           = "Sum"
  period              = var.errors_alarm.period
  evaluation_periods  = var.errors_alarm.evaluation_periods
  threshold           = var.errors_alarm.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = var.errors_alarm.treat_missing_data
  alarm_actions       = var.errors_alarm.alarm_actions
  ok_actions          = var.errors_alarm.ok_actions
  tags                = var.tags
}
