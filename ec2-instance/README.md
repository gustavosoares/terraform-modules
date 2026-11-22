# EC2 Instance Module

A small Terraform module for a single EC2 instance with its own security group, IAM role and instance profile, and an optional stop/start schedule.

## Features

- **IMDSv2 required** and **encrypted gp3 root volume** by default
- Defaults to the latest Amazon Linux 2023 AMI (x86_64), or bring your own AMI
- Instance is **not replaced** when a newer AMI is published; upgrades are deliberate
- IAM role and instance profile, with any number of managed policies attached
- Security group with ingress/egress rules by CIDR or source security group, plus extra security groups
- **No outbound access unless you allow it**: egress is empty by default
- Optional EventBridge Scheduler stop/start schedule (e.g. office hours only)
- Tags applied to all resources

## Usage

### SSM Bastion for Port-Forwarding to Private Databases

No inbound rules or SSH keys are needed. Connect with `aws ssm start-session`.

```hcl
module "bastion" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//ec2-instance?ref=v0.1.0"

  name      = "prod-bastion"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.private_subnet_ids[0]

  iam_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  egress_rules = [
    {
      description = "HTTPS for the SSM agent and AWS APIs"
      port        = 443
      cidr_ipv4   = "0.0.0.0/0"
    },
    {
      description                  = "PostgreSQL to the database"
      port                         = 5432
      referenced_security_group_id = aws_security_group.db.id
    },
  ]

  # Only run during working hours
  schedule = {
    stop     = "cron(0 20 ? * MON-FRI *)"
    start    = "cron(0 8 ? * MON-FRI *)"
    timezone = "America/New_York"
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

### General-Purpose Instance with User Data

```hcl
module "worker" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//ec2-instance?ref=v0.1.0"

  name             = "prod-worker"
  vpc_id           = module.vpc.vpc_id
  subnet_id        = module.vpc.private_subnet_ids[0]
  instance_type    = "t3.medium"
  root_volume_size = 50
  user_data        = file("${path.module}/scripts/init.sh")

  iam_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    aws_iam_policy.read_config.arn,
  ]

  ingress_rules = [
    {
      description = "App port from the VPC"
      port        = 8080
      cidr_ipv4   = "10.0.0.0/16"
    },
  ]

  egress_rules = [
    {
      description = "All outbound"
      protocol    = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    },
  ]
}
```

More complete configurations are in [examples/](./examples).

## Notes

- **AMI updates**: when `ami` is null, the latest Amazon Linux 2023 AMI is looked up, but `ami` changes are ignored after creation so new AMI releases don't replace the instance. To upgrade, run `terraform apply -replace='module.<name>.aws_instance.this'`.
- **Security group rules**: each rule needs exactly one source, `cidr_ipv4` or `referenced_security_group_id`. `port` starts the range and `to_port` (optional) ends it. `protocol` defaults to `tcp`, and `"-1"` means all traffic, in which case ports are ignored.
- **IAM names** use generated prefixes (`<name>-…`) because IAM is global per account, so the same `name` can be deployed in several regions.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Instance name (`Name` tag) and prefix for related resources | `string` | n/a | yes |
| `vpc_id` | VPC for the instance and security group | `string` | n/a | yes |
| `subnet_id` | Subnet for the instance | `string` | n/a | yes |
| `instance_type` | EC2 instance type | `string` | `"t3.micro"` | no |
| `ami` | AMI ID; null uses the latest Amazon Linux 2023 x86_64 | `string` | `null` | no |
| `user_data` | User data script | `string` | `null` | no |
| `root_volume_size` | Root volume size in GiB (gp3, encrypted) | `number` | `8` | no |
| `iam_policy_arns` | Managed policy ARNs to attach to the instance role | `list(string)` | `[]` | no |
| `ingress_rules` | Ingress rules (`description`, `port`, `to_port`, `protocol`, `cidr_ipv4` \| `referenced_security_group_id`) | `list(object)` | `[]` | no |
| `egress_rules` | Egress rules (same shape); empty = no outbound access | `list(object)` | `[]` | no |
| `additional_security_group_ids` | Extra security groups to attach | `list(string)` | `[]` | no |
| `schedule` | `{ stop, start, timezone = "UTC" }` scheduler expressions; null disables | `object` | `null` | no |
| `tags` | Tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `instance_id` | EC2 instance ID |
| `instance_arn` | EC2 instance ARN |
| `private_ip` | Private IP address |
| `ami_id` | AMI the instance was launched from |
| `security_group_id` | Instance security group ID |
| `iam_role_name` | Instance IAM role name |
| `iam_role_arn` | Instance IAM role ARN |
| `instance_profile_name` | Instance profile name |
