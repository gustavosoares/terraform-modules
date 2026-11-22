# Plan/apply against a mocked AWS provider: no credentials or real resources.
# Run from the module directory: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { id = "ami-12345678" }
  }
  mock_resource "aws_instance" {
    defaults = { arn = "arn:aws:ec2:us-east-1:111111111111:instance/i-12345678" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/example" }
  }
}

variables {
  name      = "example"
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-12345678"
}

run "defaults" {
  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }
  assert {
    condition = (
      aws_instance.this.root_block_device[0].encrypted == true &&
      aws_instance.this.root_block_device[0].volume_type == "gp3" &&
      aws_instance.this.root_block_device[0].volume_size == 8
    )
    error_message = "Root volume should be an encrypted 8 GiB gp3 volume."
  }
  assert {
    condition     = length(data.aws_ami.al2023_x86) == 1 && aws_instance.this.ami == "ami-12345678"
    error_message = "Without ami, the latest Amazon Linux 2023 AMI should be used."
  }
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 0 && length(aws_vpc_security_group_ingress_rule.this) == 0
    error_message = "No security group rules should exist by default (no outbound access)."
  }
  assert {
    condition     = length(aws_scheduler_schedule.stop) == 0 && length(aws_iam_role.scheduler) == 0
    error_message = "No schedule should be created by default."
  }
  assert {
    condition     = aws_iam_role.this.name_prefix == "example-" && aws_instance.this.tags["Name"] == "example"
    error_message = "Role should use a name prefix and the instance a Name tag."
  }
}

# Same state as "defaults": the instance already exists, so a new AMI must not
# replace it (ignore_changes = [ami]).
run "ami_change_does_not_replace" {
  variables {
    ami = "ami-87654321"
  }
  assert {
    condition     = aws_instance.this.ami == "ami-12345678"
    error_message = "Changing ami on an existing instance should be ignored."
  }
}

run "custom_ami_skips_lookup" {
  state_key = "custom_ami"
  variables {
    ami = "ami-87654321"
  }
  assert {
    condition     = length(data.aws_ami.al2023_x86) == 0 && aws_instance.this.ami == "ami-87654321"
    error_message = "A given AMI should be used without a lookup."
  }
}

run "rules_policies_and_extra_sgs" {
  variables {
    iam_policy_arns               = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
    additional_security_group_ids = ["sg-12345678"]
    ingress_rules = [
      { description = "SSH from office", port = 22, cidr_ipv4 = "10.0.0.0/16" },
    ]
    egress_rules = [
      { description = "HTTPS", port = 443, cidr_ipv4 = "0.0.0.0/0" },
      { description = "Ephemeral range", port = 1024, to_port = 65535, referenced_security_group_id = "sg-87654321" },
      { description = "All traffic", protocol = "-1", cidr_ipv4 = "10.0.0.0/16" },
    ]
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 1
    error_message = "Expected one managed policy attachment."
  }
  assert {
    condition     = contains(aws_instance.this.vpc_security_group_ids, "sg-12345678") && length(aws_instance.this.vpc_security_group_ids) == 2
    error_message = "Instance should have its own and the additional security group."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["0"].from_port == 22 && aws_vpc_security_group_ingress_rule.this["0"].to_port == 22
    error_message = "to_port should default to port."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.this["1"].to_port == 65535 && aws_vpc_security_group_egress_rule.this["1"].referenced_security_group_id == "sg-87654321"
    error_message = "Port range and security group source should be passed through."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.this["2"].from_port == null && aws_vpc_security_group_egress_rule.this["2"].ip_protocol == "-1"
    error_message = "Protocol -1 should drop the ports."
  }
}

run "schedule" {
  variables {
    schedule = {
      stop  = "cron(0 20 ? * MON-FRI *)"
      start = "cron(0 8 ? * MON-FRI *)"
    }
  }
  assert {
    condition     = length(aws_scheduler_schedule.stop) == 1 && length(aws_scheduler_schedule.start) == 1
    error_message = "Expected stop and start schedules."
  }
  assert {
    condition     = aws_scheduler_schedule.stop[0].schedule_expression_timezone == "UTC"
    error_message = "Schedule timezone should default to UTC."
  }
  assert {
    condition     = jsondecode(aws_scheduler_schedule.start[0].target[0].input).InstanceIds == [aws_instance.this.id]
    error_message = "Schedules should target this instance."
  }
}

run "rule_with_two_sources" {
  command = plan
  variables {
    ingress_rules = [
      { description = "bad", port = 22, cidr_ipv4 = "10.0.0.0/16", referenced_security_group_id = "sg-12345678" },
    ]
  }
  expect_failures = [var.ingress_rules]
}

run "rule_without_port" {
  command = plan
  variables {
    egress_rules = [
      { description = "bad", cidr_ipv4 = "0.0.0.0/0" },
    ]
  }
  expect_failures = [var.egress_rules]
}
