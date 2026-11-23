data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# IAM is global per account, so a generated prefix lets the same name be deployed
# in several regions.
resource "aws_iam_role" "this" {
  name_prefix        = "${substr(var.name, 0, 37)}-"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "logs"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  count = var.network_config != null ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "additional" {
  count = length(var.iam_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.iam_policy_arns[count.index]
}

resource "aws_iam_role_policy" "additional" {
  count = length(var.iam_policy_documents)

  name   = "additional-${count.index}"
  role   = aws_iam_role.this.id
  policy = var.iam_policy_documents[count.index]
}
