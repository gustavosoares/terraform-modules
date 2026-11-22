locals {
  # All resources are named "asg-<name>-<environment>" (or use it as a prefix).
  # The "asg-" prefix makes ASG-launched instances easy to spot in the EC2 console.
  resource_prefix = "asg-${var.name}-${var.environment}"

  tags = var.tags

  # ASG tags, propagated to instances at launch
  asg_tags = [
    for key, value in local.tags : {
      key                 = key
      value               = value
      propagate_at_launch = true
    }
  ]

  # Security group IDs
  security_group_ids = var.security_group_config.create ? concat([aws_security_group.this[0].id], var.security_group_config.existing_sg_ids) : var.security_group_config.existing_sg_ids

  # Instance profile (null = launch without one)
  instance_profile_name = var.iam_config.create_instance_profile ? aws_iam_instance_profile.this[0].name : var.iam_config.instance_profile_name

  # User data
  user_data_base64 = var.user_data_base64 != null ? var.user_data_base64 : (var.user_data != null ? base64encode(var.user_data) : null)
}

# Note: the ASG uses a fixed name together with create_before_destroy. Changes that
# force the ASG itself to be replaced (rare; launch template changes do not) will
# fail on the name conflict. Rename or destroy first in that case.
resource "aws_autoscaling_group" "this" {
  name                      = local.resource_prefix
  vpc_zone_identifier       = var.network.subnet_ids
  desired_capacity          = var.capacity.desired
  min_size                  = var.capacity.min
  max_size                  = var.capacity.max
  health_check_grace_period = var.health_check.grace_period
  health_check_type         = var.health_check.type
  default_cooldown          = var.default_cooldown
  force_delete              = var.force_delete
  termination_policies      = var.termination_policies
  enabled_metrics           = var.enabled_metrics
  suspended_processes       = var.suspended_processes
  protect_from_scale_in     = var.protect_from_scale_in
  target_group_arns         = var.target_group_arns
  load_balancers            = var.load_balancers
  wait_for_capacity_timeout = var.wait_for_capacity_timeout

  # Launch template configuration
  dynamic "launch_template" {
    for_each = var.mixed_instances_policy.enabled ? [] : [1]

    content {
      id      = aws_launch_template.this.id
      version = "$Latest"
    }
  }

  # Mixed instances policy
  dynamic "mixed_instances_policy" {
    for_each = var.mixed_instances_policy.enabled ? [1] : []

    content {
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.this.id
          version            = "$Latest"
        }

        dynamic "override" {
          for_each = var.mixed_instances_policy.override_instance_types

          content {
            instance_type     = override.value.instance_type
            weighted_capacity = override.value.weighted_capacity
          }
        }
      }

      instances_distribution {
        on_demand_allocation_strategy            = var.mixed_instances_policy.instances_distribution.on_demand_allocation_strategy
        on_demand_base_capacity                  = var.mixed_instances_policy.instances_distribution.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = var.mixed_instances_policy.instances_distribution.on_demand_percentage_above_base_capacity
        spot_allocation_strategy                 = var.mixed_instances_policy.instances_distribution.spot_allocation_strategy
        spot_instance_pools                      = var.mixed_instances_policy.instances_distribution.spot_instance_pools
        spot_max_price                           = var.mixed_instances_policy.instances_distribution.spot_max_price
      }
    }
  }

  # Instance refresh configuration
  dynamic "instance_refresh" {
    for_each = var.instance_refresh.enabled ? [1] : []

    content {
      strategy = var.instance_refresh.strategy

      preferences {
        min_healthy_percentage = var.instance_refresh.preferences.min_healthy_percentage
        instance_warmup        = var.instance_refresh.preferences.instance_warmup
        checkpoint_delay       = var.instance_refresh.preferences.checkpoint_delay
        checkpoint_percentages = var.instance_refresh.preferences.checkpoint_percentages
        auto_rollback          = var.instance_refresh.preferences.auto_rollback
      }
    }
  }

  # Warm pool configuration
  dynamic "warm_pool" {
    for_each = var.warm_pool.enabled ? [1] : []

    content {
      pool_state                  = var.warm_pool.pool_state
      min_size                    = var.warm_pool.min_size
      max_group_prepared_capacity = var.warm_pool.max_group_prepared_capacity

      instance_reuse_policy {
        reuse_on_scale_in = var.warm_pool.instance_reuse_policy.reuse_on_scale_in
      }
    }
  }

  dynamic "tag" {
    for_each = local.asg_tags

    content {
      key                 = tag.value.key
      value               = tag.value.value
      propagate_at_launch = tag.value.propagate_at_launch
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }

  depends_on = [
    aws_iam_role_policy_attachment.managed,
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy.inline
  ]
}

resource "aws_autoscaling_notification" "this" {
  count = var.enable_autoscaling_notifications ? 1 : 0

  group_names = [aws_autoscaling_group.this.name]
  topic_arn   = var.notification_topic_arn

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  lifecycle {
    precondition {
      condition     = var.notification_topic_arn != null
      error_message = "notification_topic_arn must be set when enable_autoscaling_notifications is true."
    }
  }
}

# Scaling policies
resource "aws_autoscaling_policy" "this" {
  for_each = { for policy in var.scaling_policies : policy.name => policy }

  name                      = each.value.name
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = each.value.policy_type
  adjustment_type           = each.value.adjustment_type
  scaling_adjustment        = each.value.scaling_adjustment
  cooldown                  = each.value.cooldown
  min_adjustment_magnitude  = each.value.min_adjustment_magnitude
  estimated_instance_warmup = each.value.estimated_instance_warmup

  # Target Tracking Scaling Policy
  dynamic "target_tracking_configuration" {
    for_each = each.value.target_tracking_config != null ? [each.value.target_tracking_config] : []

    content {
      target_value     = target_tracking_configuration.value.target_value
      disable_scale_in = target_tracking_configuration.value.disable_scale_in

      dynamic "predefined_metric_specification" {
        for_each = target_tracking_configuration.value.predefined_metric_specification != null ? [target_tracking_configuration.value.predefined_metric_specification] : []

        content {
          predefined_metric_type = predefined_metric_specification.value.predefined_metric_type
          resource_label         = predefined_metric_specification.value.resource_label
        }
      }

      dynamic "customized_metric_specification" {
        for_each = target_tracking_configuration.value.customized_metric_specification != null ? [target_tracking_configuration.value.customized_metric_specification] : []

        content {
          metric_name = customized_metric_specification.value.metric_name
          namespace   = customized_metric_specification.value.namespace
          statistic   = customized_metric_specification.value.statistic
          unit        = customized_metric_specification.value.unit

          dynamic "metric_dimension" {
            for_each = customized_metric_specification.value.dimensions

            content {
              name  = metric_dimension.value.name
              value = metric_dimension.value.value
            }
          }
        }
      }
    }
  }

  # Step Scaling Policy
  dynamic "step_adjustment" {
    for_each = each.value.step_adjustments

    content {
      scaling_adjustment          = step_adjustment.value.scaling_adjustment
      metric_interval_lower_bound = step_adjustment.value.metric_interval_lower_bound
      metric_interval_upper_bound = step_adjustment.value.metric_interval_upper_bound
    }
  }
}

resource "aws_autoscaling_schedule" "this" {
  for_each = { for action in var.scheduled_actions : action.name => action }

  scheduled_action_name  = each.value.name
  autoscaling_group_name = aws_autoscaling_group.this.name
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.desired_capacity
  recurrence             = each.value.recurrence
  start_time             = each.value.start_time
  end_time               = each.value.end_time
  time_zone              = each.value.time_zone
}
