resource "aws_launch_template" "this" {
  name_prefix   = "${local.resource_prefix}-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = local.user_data_base64

  dynamic "iam_instance_profile" {
    for_each = local.instance_profile_name != null ? [1] : []

    content {
      name = local.instance_profile_name
    }
  }

  vpc_security_group_ids = local.security_group_ids

  # Root block device
  block_device_mappings {
    device_name = var.root_block_device.device_name

    ebs {
      volume_type           = var.root_block_device.volume_type
      volume_size           = var.root_block_device.volume_size
      iops                  = var.root_block_device.iops
      throughput            = var.root_block_device.throughput
      encrypted             = var.root_block_device.encrypted
      kms_key_id            = var.root_block_device.kms_key_id
      delete_on_termination = var.root_block_device.delete_on_termination
    }
  }

  # Additional EBS volumes
  dynamic "block_device_mappings" {
    for_each = var.ebs_volumes
    iterator = vol

    content {
      device_name = vol.value.device_name

      ebs {
        volume_type           = vol.value.volume_type
        volume_size           = vol.value.volume_size
        iops                  = vol.value.iops
        throughput            = vol.value.throughput
        encrypted             = vol.value.encrypted
        kms_key_id            = vol.value.kms_key_id
        delete_on_termination = vol.value.delete_on_termination
        snapshot_id           = vol.value.snapshot_id
      }
    }
  }

  # Metadata options (IMDSv2)
  metadata_options {
    http_endpoint               = var.metadata_options.http_endpoint
    http_tokens                 = var.metadata_options.http_tokens
    http_put_response_hop_limit = var.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = var.metadata_options.instance_metadata_tags
  }

  # Monitoring
  monitoring {
    enabled = var.monitoring.enabled
  }

  # Placement
  dynamic "placement" {
    for_each = var.placement != null && (
      var.placement.availability_zone != null ||
      var.placement.affinity != null ||
      var.placement.group_name != null ||
      var.placement.host_id != null ||
      var.placement.tenancy != null ||
      var.placement.spread_domain != null ||
      var.placement.partition_number != null
    ) ? [1] : []

    content {
      availability_zone = var.placement.availability_zone
      affinity          = var.placement.affinity
      group_name        = var.placement.group_name
      host_id           = var.placement.host_id
      tenancy           = var.placement.tenancy
      spread_domain     = var.placement.spread_domain
      partition_number  = var.placement.partition_number
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = local.resource_prefix })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.resource_prefix}-volume" })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Persistent EBS volumes that survive instance termination
# These volumes need to be attached manually or via lifecycle hooks
resource "aws_ebs_volume" "persistent" {
  for_each = { for vol in var.persistent_volumes : vol.name => vol }

  availability_zone = each.value.availability_zone
  type              = each.value.volume_type
  size              = each.value.volume_size
  iops              = each.value.iops
  throughput        = each.value.throughput
  encrypted         = each.value.encrypted
  kms_key_id        = each.value.kms_key_id
  snapshot_id       = each.value.snapshot_id

  tags = merge(local.tags, {
    Name       = "${local.resource_prefix}-${each.key}"
    DeviceName = each.value.device_name
  })

  lifecycle {
    ignore_changes = [snapshot_id]
  }
}

# Security group configuration
resource "aws_security_group" "this" {
  count = var.security_group_config.create ? 1 : 0

  name_prefix = "${local.resource_prefix}-"
  description = "Security group for ${local.resource_prefix} ASG"
  vpc_id      = var.network.vpc_id

  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  # Expand each rule into one rule per source (CIDR or security group). Keys use
  # indices so for_each works even when sources are unknown until apply.
  sg_rules = {
    for direction, rules in {
      ingress = var.security_group_config.ingress_rules
      egress  = var.security_group_config.egress_rules
      } : direction => merge(
      {
        for pair in flatten([
          for i, r in rules : [
            for j, cidr in r.cidr_blocks : { key = "${i}-cidr-${j}", rule = r, cidr = cidr, sg = null }
          ]
        ]) : pair.key => pair
      },
      {
        for pair in flatten([
          for i, r in rules : [
            for j, sg in r.security_groups : { key = "${i}-sg-${j}", rule = r, cidr = null, sg = sg }
          ]
        ]) : pair.key => pair
      }
    )
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.security_group_config.create ? local.sg_rules.ingress : {}

  security_group_id            = aws_security_group.this[0].id
  description                  = each.value.rule.description
  ip_protocol                  = each.value.rule.protocol
  from_port                    = each.value.rule.protocol == "-1" ? null : each.value.rule.from_port
  to_port                      = each.value.rule.protocol == "-1" ? null : each.value.rule.to_port
  cidr_ipv4                    = each.value.cidr != null && !strcontains(coalesce(each.value.cidr, "x"), ":") ? each.value.cidr : null
  cidr_ipv6                    = each.value.cidr != null && strcontains(coalesce(each.value.cidr, "x"), ":") ? each.value.cidr : null
  referenced_security_group_id = each.value.sg

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.security_group_config.create ? local.sg_rules.egress : {}

  security_group_id            = aws_security_group.this[0].id
  description                  = each.value.rule.description
  ip_protocol                  = each.value.rule.protocol
  from_port                    = each.value.rule.protocol == "-1" ? null : each.value.rule.from_port
  to_port                      = each.value.rule.protocol == "-1" ? null : each.value.rule.to_port
  cidr_ipv4                    = each.value.cidr != null && !strcontains(coalesce(each.value.cidr, "x"), ":") ? each.value.cidr : null
  cidr_ipv6                    = each.value.cidr != null && strcontains(coalesce(each.value.cidr, "x"), ":") ? each.value.cidr : null
  referenced_security_group_id = each.value.sg

  tags = local.tags
}
