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

module "bastion" {
  source = "../.."

  name      = "example-bastion"
  vpc_id    = data.aws_vpc.default.id
  subnet_id = data.aws_subnets.default.ids[0]

  iam_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  egress_rules = [
    {
      description = "HTTPS for SSM agent and AWS APIs"
      port        = 443
      cidr_ipv4   = "0.0.0.0/0"
    },
    {
      description = "PostgreSQL within the VPC"
      port        = 5432
      cidr_ipv4   = data.aws_vpc.default.cidr_block
    },
    {
      description = "Redis within the VPC"
      port        = 6379
      cidr_ipv4   = data.aws_vpc.default.cidr_block
    },
  ]

  tags = {
    Project = "example"
  }
}

output "instance_id" {
  value = module.bastion.instance_id
}

output "security_group_id" {
  value = module.bastion.security_group_id
}
