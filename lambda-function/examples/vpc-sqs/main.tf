# A queue worker inside a VPC: consumes an SQS queue, reaches PostgreSQL in the
# VPC, and sends failed async invocations to a dead-letter queue. Code is
# deployed by CI, so Terraform only creates the function with a stub.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# This example uses the default VPC for brevity. In a real stack, use private
# subnets with a NAT gateway or VPC endpoints (e.g. this repo's vpc module).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_sqs_queue" "jobs" {
  name                    = "example-jobs"
  sqs_managed_sse_enabled = true

  # Must be at least the function timeout
  visibility_timeout_seconds = 180
}

module "worker" {
  source = "../.."

  name    = "example-worker"
  runtime = "nodejs22.x"
  timeout = 30

  # CI updates the code with `aws lambda update-function-code`
  ignore_code_changes = true

  network_config = {
    vpc_id     = data.aws_vpc.default.id
    subnet_ids = data.aws_subnets.default.ids

    egress_rules = {
      postgres = {
        description = "PostgreSQL within the VPC"
        from_port   = 5432
        to_port     = 5432
        cidr_blocks = [data.aws_vpc.default.cidr_block]
      }
    }
  }

  sqs_trigger = {
    queue_arn                  = aws_sqs_queue.jobs.arn
    batch_size                 = 10
    report_batch_item_failures = true
  }

  async_config = {
    maximum_retry_attempts   = 2
    create_dead_letter_queue = true
  }

  log_retention_in_days = 30

  tags = {
    Project = "example"
  }
}

output "function_name" {
  value = module.worker.function_name
}

output "security_group_id" {
  value = module.worker.security_group_id
}

output "dead_letter_queue_url" {
  value = module.worker.dead_letter_queue_url
}
