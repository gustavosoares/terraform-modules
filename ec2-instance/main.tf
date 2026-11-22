# =============================================================================
# EC2 Instance
# =============================================================================
# Creates an EC2 instance with a security group and IAM role/instance profile.
# The caller passes managed policy ARNs to attach to the role.

data "aws_ami" "al2023_x86" {
  count       = var.ami == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami = var.ami != null ? var.ami : data.aws_ami.al2023_x86[0].id
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------
# IAM names are global per account, so use generated prefixes to allow the same
# `name` in several regions.

resource "aws_iam_role" "this" {
  name_prefix = "${substr(var.name, 0, 37)}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${substr(var.name, 0, 37)}-"
  role        = aws_iam_role.this.name

  tags = merge(var.tags, { Name = var.name })
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                    = local.ami
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.this.name
  vpc_security_group_ids = concat([aws_security_group.this.id], var.additional_security_group_ids)
  user_data              = var.user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # Don't replace the instance whenever a newer AMI is published (or var.ami
    # changes). Upgrade deliberately with:
    #   terraform apply -replace='module.<name>.aws_instance.this'
    ignore_changes = [ami]
  }
}
