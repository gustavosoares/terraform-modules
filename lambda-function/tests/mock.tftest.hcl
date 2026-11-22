# Plan/apply against a mocked AWS provider: no credentials or real resources.
# Run from the module directory: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/lambda/x" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:111111111111:function:x" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-1:111111111111:x-async-dlq" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-1:111111111111:rule/x" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/x" }
  }
}

run "minimal" {
  variables { name = "test-fn" }
  assert {
    condition     = length(aws_lambda_function.this) == 1 && length(aws_lambda_function.ignore_code) == 0
    error_message = "expected managed-code resource"
  }
  assert {
    condition     = output.security_group_id == null && output.dead_letter_queue_arn == null && output.errors_alarm_arn == null
    error_message = "disabled features should output null"
  }
  assert {
    condition     = aws_lambda_function.this[0].package_type == "Zip" && aws_lambda_function.this[0].handler == "index.handler"
    error_message = "stub zip expected"
  }
}

run "everything" {
  variables {
    name                = "test-fn"
    image_uri           = "111111111111.dkr.ecr.us-east-1.amazonaws.com/x:1"
    ignore_code_changes = true
    network_config = {
      vpc_id     = "vpc-12345678"
      subnet_ids = ["subnet-12345678"]
      egress_rules = {
        pg = { description = "pg", from_port = 5432, to_port = 5432, cidr_blocks = ["10.0.0.0/16", "10.1.0.0/16"] }
      }
    }
    sqs_trigger          = { queue_arn = "arn:aws:sqs:us-east-1:111111111111:jobs", kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/x" }
    schedule             = { expression = "rate(1 hour)" }
    async_config         = { create_dead_letter_queue = true, maximum_retry_attempts = 1 }
    errors_alarm         = {}
    log_subscription     = { destination_arn = "arn:aws:lambda:us-east-1:111111111111:function:fwd" }
    iam_policy_documents = ["{}"]
    iam_policy_arns      = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }
  assert {
    condition     = length(aws_lambda_function.ignore_code) == 1 && aws_lambda_function.ignore_code[0].package_type == "Image" && aws_lambda_function.ignore_code[0].runtime == null
    error_message = "expected image function with ignored code"
  }
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.custom) == 2 && length(aws_vpc_security_group_egress_rule.https) == 1
    error_message = "expected 2 custom + 1 default egress rules"
  }
  assert {
    condition     = length(aws_lambda_event_source_mapping.sqs) == 1 && length(aws_cloudwatch_event_rule.schedule) == 1 && length(aws_cloudwatch_metric_alarm.errors) == 1
    error_message = "triggers/alarm missing"
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.errors[0].threshold == 1 && aws_sqs_queue.dead_letter[0].sqs_managed_sse_enabled == true
    error_message = "defaults not applied"
  }
}

run "two_sources_rejected" {
  command = plan
  variables {
    name      = "test-fn"
    filename  = "versions.tf"
    image_uri = "111111111111.dkr.ecr.us-east-1.amazonaws.com/x:1"
  }
  expect_failures = [aws_lambda_function.this]
}

run "bad_timeout" {
  command = plan
  variables {
    name    = "test-fn"
    timeout = 1000
  }
  expect_failures = [var.timeout]
}

run "vpc_without_subnets" {
  command = plan
  variables {
    name           = "test-fn"
    network_config = { vpc_id = "vpc-12345678", subnet_ids = [] }
  }
  expect_failures = [var.network_config]
}
