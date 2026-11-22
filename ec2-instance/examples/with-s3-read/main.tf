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

# This example uses the default VPC (public subnets) for brevity. In a real
# stack, use private subnets from a VPC module (e.g. this repo's vpc module).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_iam_policy" "bucket_read" {
  name = "example-s3-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::example-bucket/*"
    }]
  })
}

module "instance" {
  source = "../.."

  name      = "example-worker"
  vpc_id    = data.aws_vpc.default.id
  subnet_id = data.aws_subnets.default.ids[0]

  iam_policy_arns = [
    aws_iam_policy.bucket_read.arn,
  ]

  egress_rules = [
    {
      description = "HTTPS for SSM agent and AWS APIs"
      port        = 443
      cidr_ipv4   = "0.0.0.0/0"
    },
  ]

  tags = {
    Project = "example"
  }
}

output "instance_id" {
  value = module.instance.instance_id
}
