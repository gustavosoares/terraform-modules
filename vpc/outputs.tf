# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.main.arn
}

# =============================================================================
# Subnet Outputs
# =============================================================================

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "public_subnet_cidr_blocks" {
  description = "List of public subnet CIDR blocks"
  value       = [for subnet in aws_subnet.public : subnet.cidr_block]
}

output "public_subnets_by_az" {
  description = "Map of availability zone to public subnet ID"
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "private_subnet_cidr_blocks" {
  description = "List of private subnet CIDR blocks"
  value       = [for subnet in aws_subnet.private : subnet.cidr_block]
}

output "private_subnets_by_az" {
  description = "Map of availability zone to private subnet ID"
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

# =============================================================================
# Gateway Outputs
# =============================================================================

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway (first one if multiple, null if disabled). Use nat_gateway_ids for all."
  value       = var.enable_nat_gateway ? values(aws_nat_gateway.main)[0].id : null
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = var.enable_nat_gateway ? [for nat in aws_nat_gateway.main : nat.id] : []
}

output "nat_gateways_by_az" {
  description = "Map of availability zone to NAT Gateway ID"
  value       = var.enable_nat_gateway ? { for az, nat in aws_nat_gateway.main : az => nat.id } : {}
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway (first one if multiple, null if disabled). Use nat_gateway_public_ips for all."
  value       = var.enable_nat_gateway ? values(aws_eip.nat)[0].public_ip : null
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IPs"
  value       = var.enable_nat_gateway ? [for eip in aws_eip.nat : eip.public_ip] : []
}

# =============================================================================
# Route Table Outputs
# =============================================================================

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table (first one if multiple). Use private_route_table_ids for all."
  value       = values(aws_route_table.private)[0].id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = [for rt in aws_route_table.private : rt.id]
}

output "private_route_tables_by_az" {
  description = "Map of availability zone (or 'shared') to private route table ID"
  value       = { for key, rt in aws_route_table.private : key => rt.id }
}

# =============================================================================
# Availability Zone Outputs
# =============================================================================

output "availability_zones" {
  description = "List of availability zones used"
  value       = distinct(concat(keys(var.public_subnets), keys(var.private_subnets)))
}

# =============================================================================
# VPN Gateway Outputs
# =============================================================================

output "vpn_gateway_id" {
  description = "ID of the VPN Gateway (null if disabled)"
  value       = var.enable_vpn_gateway ? aws_vpn_gateway.main[0].id : (var.vpn_gateway_id != "" ? var.vpn_gateway_id : null)
}

output "vpn_gateway_arn" {
  description = "ARN of the VPN Gateway (null if disabled or using external gateway)"
  value       = var.enable_vpn_gateway ? aws_vpn_gateway.main[0].arn : null
}


# =============================================================================
# Flow Logs Outputs
# =============================================================================

output "flow_log_id" {
  description = "ID of the VPC flow log (null if disabled)"
  value       = var.do_flow_logs ? aws_flow_log.main[0].id : null
}

output "flow_logs_bucket_arn" {
  description = "ARN of the module-created flow logs bucket (null if disabled or using an existing destination)"
  value       = local.create_flow_logs_bucket ? aws_s3_bucket.flow_logs[0].arn : null
}
