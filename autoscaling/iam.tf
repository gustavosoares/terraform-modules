data "aws_iam_policy_document" "assume_role" {
  count = var.iam_config.create_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "this" {
  count = var.iam_config.create_role ? 1 : 0

  name_prefix        = "${substr(local.resource_prefix, 0, 37)}-"
  assume_role_policy = data.aws_iam_policy_document.assume_role[0].json

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = var.iam_config.create_role ? toset(var.iam_config.managed_policy_arns) : []

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

# Conditionally attach SSM policy if enable_ssm is true
resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.iam_config.create_role && var.iam_config.enable_ssm ? 1 : 0

  role       = aws_iam_role.this[0].id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.iam_config.create_role ? {
    for policy in var.iam_config.inline_policies : policy.name => policy
  } : {}

  name   = each.value.name
  role   = aws_iam_role.this[0].id
  policy = each.value.policy
}

resource "aws_iam_instance_profile" "this" {
  count = var.iam_config.create_instance_profile ? 1 : 0

  name_prefix = "${substr(local.resource_prefix, 0, 37)}-"
  role        = var.iam_config.create_role ? aws_iam_role.this[0].name : var.iam_config.role_name

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.iam_config.create_role || var.iam_config.role_name != null
      error_message = "iam_config.role_name is required when create_instance_profile is true and create_role is false."
    }
  }
}
