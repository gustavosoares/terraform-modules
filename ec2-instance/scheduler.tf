# =============================================================================
# Instance Scheduler (EventBridge Scheduler)
# =============================================================================
# Uses EventBridge Scheduler to stop and start the instance on a cron schedule.
# Only created when var.schedule is set.

resource "aws_iam_role" "scheduler" {
  count       = var.schedule != null ? 1 : 0
  name_prefix = "${substr(var.name, 0, 27)}-scheduler-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-scheduler" })
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.schedule != null ? 1 : 0
  name  = "${var.name}-scheduler"
  role  = aws_iam_role.scheduler[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:StopInstances", "ec2:StartInstances"]
      Resource = aws_instance.this.arn
    }]
  })
}

resource "aws_scheduler_schedule" "stop" {
  count = var.schedule != null ? 1 : 0
  name  = "${var.name}-stop"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule.stop
  schedule_expression_timezone = var.schedule.timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.this.id]
    })
  }
}

resource "aws_scheduler_schedule" "start" {
  count = var.schedule != null ? 1 : 0
  name  = "${var.name}-start"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule.start
  schedule_expression_timezone = var.schedule.timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.this.id]
    })
  }
}
