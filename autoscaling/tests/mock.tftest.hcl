# Plan/apply against a mocked AWS provider: no credentials or real resources.
# Run from the module directory: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/example" }
  }
}

variables {
  name        = "web"
  environment = "dev"
  ami_id      = "ami-12345678"
  network = {
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-11111111", "subnet-22222222"]
  }
}

run "defaults" {
  assert {
    condition     = aws_autoscaling_group.this.name == "asg-web-dev" && output.resource_prefix == "asg-web-dev"
    error_message = "ASG should be named asg-<name>-<environment>."
  }
  assert {
    condition = (
      aws_autoscaling_group.this.min_size == 1 &&
      aws_autoscaling_group.this.max_size == 3 &&
      aws_autoscaling_group.this.desired_capacity == 1
    )
    error_message = "Default capacity should be 1/1/3."
  }
  assert {
    condition     = length(aws_autoscaling_group.this.launch_template) == 1 && length(aws_autoscaling_group.this.mixed_instances_policy) == 0
    error_message = "Without a mixed instances policy, the ASG should use the launch template directly."
  }
  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }
  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 20
    error_message = "Root volume should be an encrypted 20 GiB volume."
  }
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 1 && aws_vpc_security_group_egress_rule.this["0-cidr-0"].ip_protocol == "-1"
    error_message = "Default security group should allow all outbound traffic."
  }
  assert {
    condition     = length(aws_iam_role.this) == 1 && length(aws_iam_instance_profile.this) == 1 && length(aws_iam_role_policy_attachment.ssm) == 0
    error_message = "A role and instance profile (without SSM) should be created by default."
  }
  assert {
    condition     = length(aws_autoscaling_notification.this) == 0 && length(aws_autoscaling_policy.this) == 0
    error_message = "No notifications or scaling policies by default."
  }
}

run "security_group_rule_expansion" {
  variables {
    security_group_config = {
      ingress_rules = [
        {
          description     = "HTTP from the ALB and the VPC"
          from_port       = 80
          to_port         = 80
          protocol        = "tcp"
          cidr_blocks     = ["10.0.0.0/16", "2001:db8::/32"]
          security_groups = ["sg-12345678"]
        },
      ]
      existing_sg_ids = ["sg-87654321"]
    }
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.this)) == toset(["0-cidr-0", "0-cidr-1", "0-sg-0"])
    error_message = "One rule should be created per source."
  }
  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.this["0-cidr-0"].cidr_ipv4 == "10.0.0.0/16" &&
      aws_vpc_security_group_ingress_rule.this["0-cidr-1"].cidr_ipv6 == "2001:db8::/32" &&
      aws_vpc_security_group_ingress_rule.this["0-sg-0"].referenced_security_group_id == "sg-12345678"
    )
    error_message = "IPv4, IPv6 and security group sources should map to the right attributes."
  }
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "Overriding security_group_config should drop the default egress rule."
  }
  assert {
    condition     = contains(aws_launch_template.this.vpc_security_group_ids, "sg-87654321") && length(aws_launch_template.this.vpc_security_group_ids) == 2
    error_message = "Launch template should use the created and existing security groups."
  }
}

run "existing_security_groups_only" {
  variables {
    security_group_config = {
      create          = false
      existing_sg_ids = ["sg-87654321"]
    }
  }
  assert {
    condition     = length(aws_security_group.this) == 0 && output.security_group_id == null
    error_message = "No security group should be created."
  }
  assert {
    condition     = aws_launch_template.this.vpc_security_group_ids == toset(["sg-87654321"])
    error_message = "Launch template should use only the existing security group."
  }
}

run "iam_ssm_and_policies" {
  variables {
    iam_config = {
      enable_ssm          = true
      managed_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
      inline_policies     = [{ name = "read-config", policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }]
    }
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1 && length(aws_iam_role_policy_attachment.managed) == 1 && length(aws_iam_role_policy.inline) == 1
    error_message = "SSM, managed and inline policies should be attached."
  }
}

run "existing_instance_profile" {
  variables {
    iam_config = {
      create_instance_profile = false
      create_role             = false
      instance_profile_name   = "my-profile"
    }
  }
  assert {
    condition     = length(aws_iam_role.this) == 0 && length(aws_iam_instance_profile.this) == 0
    error_message = "No IAM resources should be created."
  }
  assert {
    condition     = aws_launch_template.this.iam_instance_profile[0].name == "my-profile" && output.iam_role_arn == null
    error_message = "Launch template should use the existing profile."
  }
}

run "mixed_instances_refresh_warm_pool" {
  variables {
    mixed_instances_policy = {
      enabled = true
      instances_distribution = {
        on_demand_base_capacity                  = 1
        on_demand_percentage_above_base_capacity = 0
        spot_allocation_strategy                 = "price-capacity-optimized"
      }
      override_instance_types = [{ instance_type = "t3.small" }, { instance_type = "t3a.small" }]
    }
    instance_refresh = { enabled = true }
    warm_pool        = { enabled = true, min_size = 1 }
  }
  assert {
    condition     = length(aws_autoscaling_group.this.launch_template) == 0 && length(aws_autoscaling_group.this.mixed_instances_policy) == 1
    error_message = "Mixed instances policy should replace the launch_template block."
  }
  assert {
    condition     = length(aws_autoscaling_group.this.mixed_instances_policy[0].launch_template[0].override) == 2
    error_message = "Instance type overrides should be passed through."
  }
  assert {
    condition     = aws_autoscaling_group.this.instance_refresh[0].preferences[0].min_healthy_percentage == 90
    error_message = "Instance refresh should default to 90% healthy."
  }
  assert {
    condition     = aws_autoscaling_group.this.warm_pool[0].pool_state == "Stopped" && aws_autoscaling_group.this.warm_pool[0].min_size == 1
    error_message = "Warm pool settings should be passed through."
  }
}

run "scaling_schedule_and_notifications" {
  variables {
    scaling_policies = [{
      name = "cpu-50"
      target_tracking_config = {
        target_value                    = 50
        predefined_metric_specification = { predefined_metric_type = "ASGAverageCPUUtilization" }
      }
    }]
    scheduled_actions = [{
      name             = "night"
      recurrence       = "0 20 * * *"
      min_size         = 0
      max_size         = 0
      desired_capacity = 0
    }]
    enable_autoscaling_notifications = true
    notification_topic_arn           = "arn:aws:sns:us-east-1:111111111111:asg-events"
  }
  assert {
    condition     = aws_autoscaling_policy.this["cpu-50"].policy_type == "TargetTrackingScaling"
    error_message = "Target tracking policy should be created."
  }
  assert {
    condition     = aws_autoscaling_schedule.this["night"].time_zone == "UTC"
    error_message = "Scheduled action time zone should default to UTC."
  }
  assert {
    condition     = length(aws_autoscaling_notification.this[0].notifications) == 4
    error_message = "Expected launch/terminate success and error notifications."
  }
}

run "notifications_need_topic" {
  command = plan
  variables {
    enable_autoscaling_notifications = true
  }
  expect_failures = [aws_autoscaling_notification.this]
}

run "profile_without_role" {
  command = plan
  variables {
    iam_config = { create_role = false }
  }
  expect_failures = [aws_iam_instance_profile.this]
}

run "rule_without_source" {
  command = plan
  variables {
    security_group_config = {
      ingress_rules = [{ description = "bad", from_port = 22, to_port = 22, protocol = "tcp" }]
    }
  }
  expect_failures = [var.security_group_config]
}
