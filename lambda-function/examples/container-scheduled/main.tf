# A container image function that runs every hour and reads its configuration
# from Secrets Manager. Uses this repo's ecr and secrets-manager modules.
#
# Push an image to the repository before applying (the function can't be created
# without one), then let CI deploy new images: ignore_code_changes keeps
# Terraform from rolling the image back.

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

module "repo" {
  source = "../../../ecr"

  name               = "example-report"
  enable_lambda_pull = true
}

module "config" {
  source = "../../../secrets-manager"

  name        = "example-report/config"
  description = "Configuration for example-report"

  initial_secret_string = jsonencode({
    api_url = "https://api.example.com"
  })
}

module "report" {
  source = "../.."

  name                = "example-report"
  image_uri           = "${module.repo.repository_url}:v1.0.0"
  ignore_code_changes = true
  memory_size         = 1024
  timeout             = 300

  environment_variables = {
    CONFIG_SECRET_ARN = module.config.arn
  }

  iam_policy_documents = [module.config.read_policy_json]

  schedule = {
    expression  = "rate(1 hour)"
    description = "Hourly report"
  }

  tags = {
    Project = "example"
  }
}

output "repository_url" {
  value = module.repo.repository_url
}

output "function_name" {
  value = module.report.function_name
}
