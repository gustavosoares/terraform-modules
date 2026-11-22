# Plan/apply against a mocked AWS provider: no credentials or real resources.
# Run from the module directory: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::simple-vpc-flow-logs-111111111111" }
  }
}

variables {
  vpc_cidr_block = "10.0.0.0/16"
  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }
  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
    "us-east-1b" = "10.0.102.0/24"
  }
}

run "defaults_single_nat" {
  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Expected one public and one private subnet per AZ."
  }
  assert {
    condition     = length(aws_nat_gateway.main) == 1 && length(aws_eip.nat) == 1
    error_message = "Default should create a single NAT gateway."
  }
  assert {
    condition     = keys(aws_nat_gateway.main) == ["us-east-1a"]
    error_message = "Single NAT gateway should default to the first public subnet AZ."
  }
  assert {
    condition     = keys(aws_route_table.private) == ["shared"] && length(aws_route.private_nat) == 1
    error_message = "Single NAT should use one shared private route table with a NAT route."
  }
  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets should not auto-assign public IPs by default."
  }
  assert {
    condition     = length(aws_flow_log.main) == 0 && length(aws_vpn_gateway.main) == 0
    error_message = "Flow logs and VPN gateway should be off by default."
  }
  assert {
    condition     = output.flow_log_id == null && output.vpn_gateway_id == null && length(output.nat_gateway_ids) == 1
    error_message = "Outputs for disabled features should be null."
  }
}

run "nat_gateway_az_override" {
  variables {
    nat_gateway_az = "us-east-1b"
  }
  assert {
    condition     = keys(aws_nat_gateway.main) == ["us-east-1b"]
    error_message = "nat_gateway_az should choose the NAT gateway's AZ."
  }
}

run "nat_per_az" {
  variables {
    single_nat_gateway = false
  }
  assert {
    condition     = length(aws_nat_gateway.main) == 2 && length(aws_eip.nat) == 2
    error_message = "Expected one NAT gateway per AZ."
  }
  assert {
    condition     = toset(keys(aws_route_table.private)) == toset(["us-east-1a", "us-east-1b"]) && length(aws_route.private_nat) == 2
    error_message = "Expected one private route table and NAT route per AZ."
  }
  assert {
    condition     = aws_route.private_nat["us-east-1b"].nat_gateway_id == aws_nat_gateway.main["us-east-1b"].id
    error_message = "Each private route table should route through its own AZ's NAT gateway."
  }
}

run "no_nat" {
  variables {
    enable_nat_gateway = false
  }
  assert {
    condition     = length(aws_nat_gateway.main) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "No NAT resources should be created."
  }
  assert {
    condition     = output.nat_gateway_id == null && output.nat_gateway_ids == []
    error_message = "NAT outputs should be empty when disabled."
  }
}

run "flow_logs_module_bucket" {
  variables {
    do_flow_logs = true
  }
  assert {
    condition     = aws_s3_bucket.flow_logs[0].bucket == "simple-vpc-flow-logs-111111111111"
    error_message = "Flow logs bucket name should be <name_prefix>-vpc-flow-logs-<account>."
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.flow_logs[0].block_public_acls &&
      aws_s3_bucket_public_access_block.flow_logs[0].block_public_policy &&
      aws_s3_bucket_public_access_block.flow_logs[0].ignore_public_acls &&
      aws_s3_bucket_public_access_block.flow_logs[0].restrict_public_buckets
    )
    error_message = "Flow logs bucket must block all public access."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.flow_logs[0].rule[0].expiration[0].days == 90
    error_message = "Flow logs should expire after 90 days by default."
  }
  assert {
    condition     = aws_flow_log.main[0].traffic_type == "ALL" && aws_flow_log.main[0].log_destination == aws_s3_bucket.flow_logs[0].arn
    error_message = "Flow log should capture ALL traffic into the module bucket."
  }
}

run "flow_logs_keep_forever" {
  variables {
    do_flow_logs             = true
    flow_logs_retention_days = 0
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.flow_logs) == 0
    error_message = "Retention 0 should create no lifecycle rule."
  }
}

run "flow_logs_existing_destination" {
  variables {
    do_flow_logs              = true
    flow_logs_destination_arn = "arn:aws:s3:::my-central-flow-logs/vpc"
  }
  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0 && output.flow_logs_bucket_arn == null
    error_message = "No bucket should be created when a destination is given."
  }
  assert {
    condition     = aws_flow_log.main[0].log_destination == "arn:aws:s3:::my-central-flow-logs/vpc"
    error_message = "Flow log should use the given destination."
  }
}

run "vpn_gateway_with_propagation" {
  variables {
    enable_vpn_gateway                 = true
    propagate_private_route_tables_vgw = true
  }
  assert {
    condition     = length(aws_vpn_gateway.main) == 1 && aws_vpn_gateway.main[0].amazon_side_asn == "64512"
    error_message = "Expected a VPN gateway with the default ASN."
  }
  assert {
    condition     = length(aws_vpn_gateway_route_propagation.private) == 1 && length(aws_vpn_gateway_route_propagation.public) == 0
    error_message = "Only private route tables should propagate VGW routes."
  }
}

run "existing_vpn_gateway" {
  variables {
    vpn_gateway_id                    = "vgw-12345678"
    propagate_public_route_tables_vgw = true
  }
  assert {
    condition     = length(aws_vpn_gateway.main) == 0 && length(aws_vpn_gateway_attachment.main) == 1
    error_message = "An existing VPN gateway should be attached, not created."
  }
  assert {
    condition     = aws_vpn_gateway_route_propagation.public[0].vpn_gateway_id == "vgw-12345678" && output.vpn_gateway_id == "vgw-12345678"
    error_message = "Propagation and output should use the existing gateway."
  }
}

run "invalid_cidr" {
  command = plan
  variables {
    vpc_cidr_block = "10.0.0.0/33"
  }
  expect_failures = [var.vpc_cidr_block]
}

run "empty_private_subnets" {
  command = plan
  variables {
    private_subnets = {}
  }
  expect_failures = [var.private_subnets]
}

run "invalid_traffic_type" {
  command = plan
  variables {
    flow_logs_traffic_type = "SOME"
  }
  expect_failures = [var.flow_logs_traffic_type]
}
