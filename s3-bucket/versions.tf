terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.22.0 added rule.blocked_encryption_types on aws_s3_bucket_server_side_encryption_configuration
      version = ">= 6.22.0"
    }
  }
}
