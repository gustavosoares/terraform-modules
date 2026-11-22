variable "name" {
  type        = string
  description = "Base name for the Auto Scaling Group and associated resources. Resources are named 'asg-<name>-<environment>'."
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod). Appended to resource names."
}

variable "network" {
  type = object({
    vpc_id     = string
    subnet_ids = list(string)
  })
  description = <<EOT
  The network information.
  vpc_id: The ID of the VPC.
  subnet_ids: List of subnet IDs for the ASG instances.
  EOT
}

variable "ami_id" {
  type        = string
  description = "The AMI ID to use for the instances."
}

variable "instance_type" {
  type        = string
  description = "The EC2 instance type."
  default     = "t3.micro"
}

variable "key_name" {
  type        = string
  description = "The SSH key pair name for instance access."
  default     = null
}

variable "user_data" {
  type        = string
  description = "The user data script to run on instance launch."
  default     = null
}

variable "user_data_base64" {
  type        = string
  description = "Base64-encoded user data script. Takes precedence over user_data if both are provided."
  default     = null
}

variable "capacity" {
  type = object({
    desired = number
    min     = number
    max     = number
  })
  description = <<EOT
  The capacity configuration for the ASG.
  desired: The desired number of instances.
  min: The minimum number of instances.
  max: The maximum number of instances.
  EOT
  default = {
    desired = 1
    min     = 1
    max     = 3
  }
}

variable "health_check" {
  type = object({
    type         = string
    grace_period = number
  })
  description = <<EOT
  Health check configuration.
  type: The type of health check (EC2 or ELB).
  grace_period: Time (in seconds) after instance comes into service before checking health.
  EOT
  default = {
    type         = "EC2"
    grace_period = 300
  }
}

variable "instance_refresh" {
  type = object({
    enabled  = bool
    strategy = optional(string, "Rolling")
    preferences = optional(object({
      min_healthy_percentage = optional(number, 90)
      instance_warmup        = optional(number, 300)
      checkpoint_delay       = optional(number, 3600)
      checkpoint_percentages = optional(list(number), [])
      auto_rollback          = optional(bool, true)
    }), {})
  })
  description = <<EOT
  Instance refresh configuration for updating instances.
  enabled: Whether to enable instance refresh.
  strategy: The strategy to use (Rolling is currently the only supported value).
  preferences: Configuration for the refresh process.
  EOT
  default = {
    enabled  = false
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 90
      instance_warmup        = 300
    }
  }
}

variable "ebs_volumes" {
  type = list(object({
    device_name           = string
    volume_type           = optional(string, "gp3")
    volume_size           = number
    iops                  = optional(number, null)
    throughput            = optional(number, null)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string, null)
    delete_on_termination = optional(bool, true)
    snapshot_id           = optional(string, null)
  }))
  description = <<EOT
  List of EBS volumes to attach to instances.
  device_name: The device name to attach (e.g., /dev/sdf).
  volume_type: The volume type (gp2, gp3, io1, io2, st1, sc1).
  volume_size: The size of the volume in GiB.
  iops: The number of IOPS (only for io1, io2, gp3).
  throughput: The throughput in MB/s (only for gp3).
  encrypted: Whether to encrypt the volume.
  kms_key_id: The KMS key ID for encryption.
  delete_on_termination: Whether to delete the volume on instance termination.
  snapshot_id: The snapshot ID to restore from.
  EOT
  default     = []
}

variable "root_block_device" {
  type = object({
    device_name           = optional(string, "/dev/xvda")
    volume_type           = optional(string, "gp3")
    volume_size           = optional(number, 20)
    iops                  = optional(number, null)
    throughput            = optional(number, null)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string, null)
    delete_on_termination = optional(bool, true)
  })
  description = <<EOT
  Root block device configuration.
  device_name: The device name (e.g., /dev/xvda for Linux, /dev/sda1 for Windows).
  volume_type: The volume type (gp2, gp3, io1, io2).
  volume_size: The size of the volume in GiB.
  iops: The number of IOPS (only for io1, io2, gp3).
  throughput: The throughput in MB/s (only for gp3).
  encrypted: Whether to encrypt the volume.
  kms_key_id: The KMS key ID for encryption.
  delete_on_termination: Whether to delete the volume on instance termination.
  EOT
  default = {
    device_name           = "/dev/xvda"
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }
}

variable "persistent_volumes" {
  type = list(object({
    name              = string
    device_name       = string
    availability_zone = string
    volume_type       = optional(string, "gp3")
    volume_size       = number
    iops              = optional(number, null)
    throughput        = optional(number, null)
    encrypted         = optional(bool, true)
    kms_key_id        = optional(string, null)
    snapshot_id       = optional(string, null)
  }))
  description = <<EOT
  List of persistent EBS volumes that persist across instance replacements.
  These volumes are created outside the ASG and can be attached via lifecycle hooks.
  name: A unique name for the volume.
  device_name: The device name to attach (e.g., /dev/sdh).
  availability_zone: The AZ where the volume should be created.
  volume_type: The volume type (gp2, gp3, io1, io2, st1, sc1).
  volume_size: The size of the volume in GiB.
  iops: The number of IOPS (only for io1, io2, gp3).
  throughput: The throughput in MB/s (only for gp3).
  encrypted: Whether to encrypt the volume.
  kms_key_id: The KMS key ID for encryption.
  snapshot_id: The snapshot ID to restore from.
  EOT
  default     = []
}

variable "security_group_config" {
  type = object({
    create          = optional(bool, true)
    existing_sg_ids = optional(list(string), [])
    ingress_rules = optional(list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
    })), [])
    egress_rules = optional(list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
    })), [])
  })
  description = <<EOT
  Security group configuration.
  create: Whether to create a new security group.
  existing_sg_ids: Existing security group IDs to attach (in addition to the created group when create is true).
  ingress_rules: Ingress rules for the created group. Each rule needs at least one source:
    cidr_blocks (IPv4 or IPv6) and/or security_groups. One rule is created per source.
    Use protocol "-1" for all traffic (ports are ignored).
  egress_rules: Egress rules for the created group (same shape as ingress_rules).
  EOT
  default = {
    create        = true
    ingress_rules = []
    egress_rules = [
      {
        description = "Allow all outbound traffic"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ]
  }

  validation {
    condition = alltrue([
      for r in concat(var.security_group_config.ingress_rules, var.security_group_config.egress_rules) :
      length(r.cidr_blocks) + length(r.security_groups) > 0
    ])
    error_message = "Each security group rule must set at least one of cidr_blocks or security_groups."
  }
}

variable "iam_config" {
  type = object({
    create_instance_profile = optional(bool, true)
    instance_profile_name   = optional(string, null)
    create_role             = optional(bool, true)
    role_name               = optional(string, null)
    enable_ssm              = optional(bool, false)
    managed_policy_arns     = optional(list(string), [])
    inline_policies = optional(list(object({
      name   = string
      policy = string
    })), [])
  })
  description = <<EOT
  IAM configuration for the instances.
  create_instance_profile: Create an instance profile (named with a generated prefix).
  instance_profile_name: Existing instance profile to use when create_instance_profile is false. Leave null for no profile.
  create_role: Create an IAM role (named with a generated prefix) for the instance profile.
  role_name: Existing IAM role for the created instance profile. Required when create_instance_profile is true and create_role is false.
  enable_ssm: Attach AmazonSSMManagedInstanceCore to the created role for Systems Manager access.
  managed_policy_arns: Managed policy ARNs to attach to the created role.
  inline_policies: Inline policies to attach to the created role.
  EOT
  default = {
    create_instance_profile = true
    create_role             = true
    enable_ssm              = false
    managed_policy_arns     = []
  }
}

variable "scaling_policies" {
  type = list(object({
    name                      = string
    policy_type               = optional(string, "TargetTrackingScaling")
    adjustment_type           = optional(string, null)
    scaling_adjustment        = optional(number, null)
    cooldown                  = optional(number, null)
    estimated_instance_warmup = optional(number, null)

    # Target Tracking Configuration
    target_tracking_config = optional(object({
      target_value = number
      predefined_metric_specification = optional(object({
        predefined_metric_type = string
        resource_label         = optional(string, null)
      }), null)
      customized_metric_specification = optional(object({
        metric_name = string
        namespace   = string
        statistic   = string
        unit        = optional(string, null)
        dimensions = optional(list(object({
          name  = string
          value = string
        })), [])
      }), null)
      disable_scale_in = optional(bool, false)
    }), null)

    # Step Scaling Configuration
    step_adjustments = optional(list(object({
      scaling_adjustment          = number
      metric_interval_lower_bound = optional(number, null)
      metric_interval_upper_bound = optional(number, null)
    })), [])

    # Simple Scaling Configuration
    min_adjustment_magnitude = optional(number, null)
  }))
  description = <<EOT
  List of scaling policies to create.
  name: The name of the scaling policy.
  policy_type: The type of policy (TargetTrackingScaling, StepScaling, SimpleScaling).
  
  For Target Tracking:
  - target_tracking_config: Configuration for target tracking scaling.
  
  For Step Scaling:
  - adjustment_type: The adjustment type (ChangeInCapacity, ExactCapacity, PercentChangeInCapacity).
  - step_adjustments: List of step adjustments.
  - estimated_instance_warmup: The estimated time for a newly launched instance to contribute.
  
  For Simple Scaling:
  - adjustment_type: The adjustment type.
  - scaling_adjustment: The amount to scale.
  - cooldown: The cooldown period.
  EOT
  default     = []
}

variable "scheduled_actions" {
  type = list(object({
    name             = string
    min_size         = optional(number, null)
    max_size         = optional(number, null)
    desired_capacity = optional(number, null)
    recurrence       = optional(string, null)
    start_time       = optional(string, null)
    end_time         = optional(string, null)
    time_zone        = optional(string, "UTC")
  }))
  description = <<EOT
  List of scheduled scaling actions.
  name: The name of the scheduled action.
  min_size: The minimum size for the ASG during this action.
  max_size: The maximum size for the ASG during this action.
  desired_capacity: The desired capacity during this action.
  recurrence: Cron expression for recurring actions.
  start_time: The start time for the action (ISO 8601 format).
  end_time: The end time for the action (ISO 8601 format).
  time_zone: The time zone for the schedule.
  EOT
  default     = []
}

variable "target_group_arns" {
  type        = list(string)
  description = "List of target group ARNs to associate with the ASG."
  default     = []
}

variable "load_balancers" {
  type        = list(string)
  description = "List of classic load balancer names to associate with the ASG."
  default     = []
}

variable "termination_policies" {
  type        = list(string)
  description = "List of termination policies for the ASG (e.g., OldestInstance, NewestInstance, Default)."
  default     = ["Default"]
}

variable "enabled_metrics" {
  type        = list(string)
  description = "List of CloudWatch metrics to enable for the ASG."
  default = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
}

variable "suspended_processes" {
  type        = list(string)
  description = "List of processes to suspend for the ASG (e.g., Launch, Terminate, HealthCheck)."
  default     = []
}

variable "metadata_options" {
  type = object({
    http_endpoint               = optional(string, "enabled")
    http_tokens                 = optional(string, "required")
    http_put_response_hop_limit = optional(number, 1)
    instance_metadata_tags      = optional(string, "disabled")
  })
  description = <<EOT
  Metadata options for the launch template.
  http_endpoint: Whether the metadata service is enabled (enabled or disabled).
  http_tokens: Whether tokens are required (required or optional).
  http_put_response_hop_limit: The desired HTTP PUT response hop limit.
  instance_metadata_tags: Enable instance metadata tags (enabled or disabled).
  EOT
  default = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
}

variable "monitoring" {
  type = object({
    enabled = optional(bool, false)
  })
  description = <<EOT
  Monitoring configuration.
  enabled: Enable EC2 detailed (1-minute) monitoring. Incurs additional CloudWatch charges.
  EOT
  default = {
    enabled = false
  }
}

variable "placement" {
  type = object({
    availability_zone = optional(string, null)
    affinity          = optional(string, null)
    group_name        = optional(string, null)
    host_id           = optional(string, null)
    tenancy           = optional(string, null)
    spread_domain     = optional(string, null)
    partition_number  = optional(number, null)
  })
  description = <<EOT
  Placement configuration for instances.
  availability_zone: The AZ to launch instances in.
  affinity: The affinity setting for instances.
  group_name: The name of the placement group.
  host_id: The ID of the dedicated host.
  tenancy: The tenancy (default, dedicated, host).
  spread_domain: The spread domain for spread placement groups.
  partition_number: The partition number for partition placement groups.
  EOT
  default     = {}
}

variable "mixed_instances_policy" {
  type = object({
    enabled = optional(bool, false)
    instances_distribution = optional(object({
      on_demand_allocation_strategy            = optional(string, "prioritized")
      on_demand_base_capacity                  = optional(number, 0)
      on_demand_percentage_above_base_capacity = optional(number, 100)
      spot_allocation_strategy                 = optional(string, "lowest-price")
      spot_instance_pools                      = optional(number, 2)
      spot_max_price                           = optional(string, null)
    }), {})
    override_instance_types = optional(list(object({
      instance_type     = string
      weighted_capacity = optional(number, null)
    })), [])
  })
  description = <<EOT
  Mixed instances policy for using Spot and On-Demand instances.
  enabled: Whether to enable mixed instances policy.
  instances_distribution: Configuration for instance distribution.
  override_instance_types: List of instance types to override.
  EOT
  default = {
    enabled = false
  }
}

variable "warm_pool" {
  type = object({
    enabled                     = optional(bool, false)
    pool_state                  = optional(string, "Stopped")
    min_size                    = optional(number, 0)
    max_group_prepared_capacity = optional(number, null)
    instance_reuse_policy = optional(object({
      reuse_on_scale_in = optional(bool, true)
    }), {})
  })
  description = <<EOT
  Warm pool configuration for pre-initialized instances.
  enabled: Whether to enable warm pool.
  pool_state: The state of instances in the warm pool (Stopped, Running, Hibernated).
  min_size: The minimum number of instances in the warm pool.
  max_group_prepared_capacity: The maximum group prepared capacity.
  instance_reuse_policy: Configuration for reusing instances.
  EOT
  default = {
    enabled = false
  }
}

variable "protect_from_scale_in" {
  type        = bool
  description = "Whether newly launched instances are protected from scale in."
  default     = false
}

variable "default_cooldown" {
  type        = number
  description = "The amount of time, in seconds, after a scaling activity completes before another can start."
  default     = 300
}

variable "force_delete" {
  type        = bool
  description = "Whether to force delete the ASG without waiting for instances to drain."
  default     = false
}

variable "wait_for_capacity_timeout" {
  type        = string
  description = "Maximum duration to wait for ASG capacity on creation/update."
  default     = "10m"
}

variable "enable_autoscaling_notifications" {
  type        = bool
  description = "Publish ASG launch/terminate events (and errors) to the SNS topic in notification_topic_arn."
  default     = false
}

variable "notification_topic_arn" {
  type        = string
  description = "SNS topic ARN for ASG notifications (launch/terminate success and error). Required when enable_autoscaling_notifications is true."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources."
  default     = {}
}
