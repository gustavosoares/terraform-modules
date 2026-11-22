# Auto Scaling Group Module

A Terraform module for an EC2 Auto Scaling Group with a launch template, security group, IAM instance profile, scaling policies, and optional Spot, warm pool, and instance refresh support.

## Features

- Launch template–based ASG across multiple subnets/AZs
- **IMDSv2 required** and **encrypted EBS volumes** by default
- Root volume, additional EBS volumes, and standalone persistent EBS volumes
- Security group with ingress/egress rules (CIDR and/or source security group, IPv4 and IPv6), or bring your own
- IAM role and instance profile with optional SSM Session Manager access, managed and inline policies, or bring your own
- Scaling policies: target tracking, step, and simple scaling, plus scheduled actions
- Mixed instances policy (Spot + On-Demand), warm pools, and instance refresh with auto-rollback
- ALB/NLB target group and Classic ELB attachment
- Optional SNS notifications for launch/terminate events
- Tags applied to all resources and propagated to instances

## Naming

All resources are named (or prefixed) `asg-<name>-<environment>`, so instances launched by an ASG are easy to tell apart in the EC2 console. For example, `name = "web"` and `environment = "prod"` give:

| Resource | Name |
|----------|------|
| Auto Scaling Group | `asg-web-prod` |
| Launch template, IAM role, instance profile, security group | `asg-web-prod-<random suffix>` |
| Instances (`Name` tag) | `asg-web-prod` |
| Root/additional volumes (`Name` tag) | `asg-web-prod-volume` |
| Persistent volumes | `asg-web-prod-<volume name>` |

Use the `resource_prefix` output to name related resources (load balancers, target groups) consistently.

Keep `name` and `environment` short. AWS limits load balancer and target group names to 32 characters, so `"${module.x.resource_prefix}-alb"` must fit in that. IAM name prefixes are truncated automatically.

The ASG uses a fixed name together with `create_before_destroy`. Launch template changes roll out without replacing the ASG. A change that does force replacement of the ASG itself fails on the name conflict, so rename or destroy the ASG first in that case.

## Usage

### Basic Example

```hcl
module "web_asg" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//autoscaling?ref=v0.1.0"

  name        = "web"
  environment = "prod"
  ami_id      = data.aws_ami.al2023.id

  network = {
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnet_ids
  }

  capacity = {
    desired = 2
    min     = 1
    max     = 5
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

### Behind an Application Load Balancer

```hcl
module "web_asg" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//autoscaling?ref=v0.1.0"

  name        = "web"
  environment = "prod"
  ami_id      = data.aws_ami.al2023.id

  network = {
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnet_ids
  }

  health_check = {
    type         = "ELB"
    grace_period = 300
  }

  target_group_arns = [aws_lb_target_group.web.arn]

  security_group_config = {
    ingress_rules = [
      {
        description     = "HTTP from the ALB"
        from_port       = 80
        to_port         = 80
        protocol        = "tcp"
        security_groups = [aws_security_group.alb.id]
      }
    ]
    egress_rules = [
      {
        description = "All outbound"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ]
  }
}
```

See [examples/with-alb](./examples/with-alb) for a complete configuration including the ALB, target group, and listener.

### Custom Instance Type and Storage

```hcl
module "compute_asg" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//autoscaling?ref=v0.1.0"

  name          = "compute"
  environment   = "prod"
  ami_id        = data.aws_ami.al2023.id
  instance_type = "c7i.2xlarge"

  network = {
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnet_ids
  }

  root_block_device = {
    volume_size = 100
    iops        = 3000
    throughput  = 250
  }

  ebs_volumes = [
    {
      device_name = "/dev/sdf"
      volume_size = 500
      iops        = 10000
      throughput  = 500
    }
  ]
}
```

### Target Tracking and Scheduled Scaling

```hcl
module "api_asg" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//autoscaling?ref=v0.1.0"

  name        = "api"
  environment = "prod"
  ami_id      = data.aws_ami.al2023.id

  network = {
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnet_ids
  }

  capacity = {
    desired = 2
    min     = 2
    max     = 20
  }

  scaling_policies = [
    {
      name = "cpu-target-tracking"
      target_tracking_config = {
        target_value = 60
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
      }
    }
  ]

  scheduled_actions = [
    {
      name             = "scale-down-nightly"
      recurrence       = "0 22 * * *"
      min_size         = 1
      max_size         = 2
      desired_capacity = 1
      time_zone        = "UTC"
    }
  ]
}
```

### Spot Instances with a Mixed Instances Policy

```hcl
module "workers_asg" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//autoscaling?ref=v0.1.0"

  name        = "workers"
  environment = "prod"
  ami_id      = data.aws_ami.al2023.id

  network = {
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnet_ids
  }

  mixed_instances_policy = {
    enabled = true
    instances_distribution = {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
    override_instance_types = [
      { instance_type = "m6i.large" },
      { instance_type = "m7i.large" },
      { instance_type = "m6a.large" },
    ]
  }
}
```

### SSM Access and Custom IAM Policies

```hcl
module "app_asg" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//autoscaling?ref=v0.1.0"

  name        = "app"
  environment = "prod"
  ami_id      = data.aws_ami.al2023.id

  network = {
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnet_ids
  }

  iam_config = {
    enable_ssm          = true
    managed_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
    inline_policies = [
      {
        name   = "read-config-bucket"
        policy = data.aws_iam_policy_document.read_config.json
      }
    ]
  }
}
```

To use existing IAM resources instead, either set `create_instance_profile = false` and pass `instance_profile_name`, or set `create_role = false` and pass `role_name` for the created profile.

## Notes

- **Desired capacity** is ignored after creation (`ignore_changes = [desired_capacity]`) so Terraform doesn't fight scaling policies. Change `min`/`max` to move it.
- **Persistent volumes** (`persistent_volumes`) are standalone EBS volumes that survive instance replacement. The module creates them but does **not** attach them. Attach them from user data or a lifecycle hook, and make sure each volume's `availability_zone` matches where the instance runs.
- **Security groups**: with `create = true`, each rule becomes one rule per CIDR and per source security group. Protocol `"-1"` means all traffic, and its ports are ignored. `existing_sg_ids` are attached in addition to the created group.
- **Default egress**: the created security group allows all outbound traffic by default. Pass `egress_rules = []` to remove that.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| `name` | Base name for the ASG and associated resources | `string` |
| `environment` | Environment name, appended to resource names | `string` |
| `network` | `{ vpc_id, subnet_ids }` | `object` |
| `ami_id` | AMI ID for the instances | `string` |

### Instances

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `instance_type` | EC2 instance type | `string` | `"t3.micro"` |
| `key_name` | SSH key pair name | `string` | `null` |
| `user_data` | User data script (plain text) | `string` | `null` |
| `user_data_base64` | Base64 user data; takes precedence over `user_data` | `string` | `null` |
| `metadata_options` | IMDS settings (`http_tokens`, hop limit, …) | `object` | IMDSv2 required |
| `monitoring` | `{ enabled }` for detailed monitoring | `object` | `{ enabled = false }` |
| `placement` | Placement group / tenancy settings | `object` | `{}` |
| `root_block_device` | Root volume settings | `object` | 20 GiB gp3, encrypted |
| `ebs_volumes` | Additional volumes in the launch template | `list(object)` | `[]` |
| `persistent_volumes` | Standalone EBS volumes that outlive instances | `list(object)` | `[]` |

### Capacity and Scaling

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `capacity` | `{ desired, min, max }` | `object` | `{ 1, 1, 3 }` |
| `health_check` | `{ type = EC2 \| ELB, grace_period }` | `object` | `{ "EC2", 300 }` |
| `scaling_policies` | Target tracking, step, or simple scaling policies | `list(object)` | `[]` |
| `scheduled_actions` | Scheduled capacity changes | `list(object)` | `[]` |
| `mixed_instances_policy` | Spot/On-Demand mix and instance type overrides | `object` | `{ enabled = false }` |
| `warm_pool` | Pre-initialized instance pool | `object` | `{ enabled = false }` |
| `instance_refresh` | Rolling replacement on launch template changes | `object` | `{ enabled = false }` |
| `termination_policies` | Termination policy order | `list(string)` | `["Default"]` |
| `enabled_metrics` | ASG group metrics to publish | `list(string)` | all `Group*` metrics |
| `suspended_processes` | ASG processes to suspend | `list(string)` | `[]` |
| `protect_from_scale_in` | Protect new instances from scale-in | `bool` | `false` |
| `default_cooldown` | Seconds between scaling activities | `number` | `300` |
| `force_delete` | Delete without waiting for instances to terminate | `bool` | `false` |
| `wait_for_capacity_timeout` | Max wait for capacity on create/update | `string` | `"10m"` |

### Networking, IAM, and Integrations

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `security_group_config` | `{ create, existing_sg_ids, ingress_rules, egress_rules }` | `object` | create, all egress |
| `iam_config` | Role/instance profile creation, SSM, policies | `object` | create both |
| `target_group_arns` | ALB/NLB target groups | `list(string)` | `[]` |
| `load_balancers` | Classic ELB names | `list(string)` | `[]` |
| `enable_autoscaling_notifications` | Publish launch/terminate events to SNS | `bool` | `false` |
| `notification_topic_arn` | SNS topic (required when notifications are enabled) | `string` | `null` |
| `tags` | Tags for all resources (propagated to instances) | `map(string)` | `{}` |

See [variables.tf](./variables.tf) for the full object schemas.

## Outputs

| Name | Description |
|------|-------------|
| `resource_prefix` | Naming prefix used for all resources (`asg-<name>-<environment>`) |
| `asg_id` / `asg_name` / `asg_arn` | Auto Scaling Group identifiers |
| `launch_template_id` / `launch_template_arn` | Launch template identifiers |
| `launch_template_latest_version` | Latest launch template version |
| `security_group_id` / `security_group_arn` | Created security group (null if not created) |
| `iam_role_id` / `iam_role_arn` / `iam_role_name` | Created IAM role (null if not created) |
| `iam_instance_profile_id` / `iam_instance_profile_arn` | Created instance profile (null if not created) |
| `iam_instance_profile_name` | Instance profile used by instances (created or existing) |
| `scaling_policy_arns` | Map of scaling policy name to ARN |
| `persistent_volume_ids` / `persistent_volume_arns` | Maps of persistent volume name to ID/ARN |
