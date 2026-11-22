# A Python function packaged from ./src, with an errors alarm that notifies an
# SNS topic.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.terraform/build/hello.zip"
}

resource "aws_sns_topic" "alerts" {
  name = "example-lambda-alerts"
}

module "hello" {
  source = "../.."

  name        = "example-hello"
  description = "Example function"

  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  runtime          = "python3.13"
  architectures    = ["arm64"]

  environment_variables = {
    LOG_LEVEL = "info"
  }

  errors_alarm = {
    alarm_actions = [aws_sns_topic.alerts.arn]
    ok_actions    = [aws_sns_topic.alerts.arn]
  }

  tags = {
    Project = "example"
  }
}

output "function_name" {
  value = module.hello.function_name
}

output "function_arn" {
  value = module.hello.function_arn
}
