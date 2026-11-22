resource "aws_security_group" "this" {
  count = var.network_config != null ? 1 : 0

  name_prefix = "${var.name}-"
  description = "Lambda function ${var.name}"
  vpc_id      = var.network_config.vpc_id
  tags        = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  count = var.network_config != null && try(var.network_config.enable_default_egress, false) ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "HTTPS to anywhere (AWS APIs and external services)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
  tags              = var.tags
}

locals {
  # One rule resource per (rule, CIDR) pair, as the VPC rule resources take a single CIDR.
  egress_rules = var.network_config == null ? {} : merge([
    for key, rule in var.network_config.egress_rules : {
      for cidr in rule.cidr_blocks : "${key}-${cidr}" => merge(rule, { cidr = cidr })
    }
  ]...)
}

resource "aws_vpc_security_group_egress_rule" "custom" {
  for_each = local.egress_rules

  security_group_id = aws_security_group.this[0].id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_ipv4         = each.value.cidr
  tags              = var.tags
}
