# =============================================================================
# Required Variables
# =============================================================================

variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block for the VPC (e.g., '10.0.0.0/16' or '172.30.0.0/16')"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR block."
  }
}

variable "public_subnets" {
  type        = map(string)
  description = <<-EOT
    Map of availability zone to CIDR block for public subnets.
    Example:
      {
        "us-east-1a" = "10.0.1.0/24"
        "us-east-1b" = "10.0.2.0/24"
      }
  EOT

  validation {
    condition     = length(var.public_subnets) > 0
    error_message = "At least one public subnet must be defined."
  }
}

variable "private_subnets" {
  type        = map(string)
  description = <<-EOT
    Map of availability zone to CIDR block for private subnets.
    Example:
      {
        "us-east-1a" = "10.0.101.0/24"
        "us-east-1b" = "10.0.102.0/24"
      }
  EOT

  validation {
    condition     = length(var.private_subnets) > 0
    error_message = "At least one private subnet must be defined."
  }
}

# =============================================================================
# Optional Variables
# =============================================================================

variable "vpc_name" {
  type        = string
  description = "Name tag for the VPC"
  default     = "simple-vpc"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names (subnets, route tables, etc.)"
  default     = "simple"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames in the VPC"
  default     = true
}

variable "enable_dns_support" {
  type        = bool
  description = "Enable DNS support in the VPC"
  default     = true
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Create NAT gateway(s) for private subnet internet access"
  default     = true
}

variable "single_nat_gateway" {
  type        = bool
  description = <<-EOT
    Use a single NAT gateway for all private subnets (cost-effective).
    When false, creates one NAT gateway per AZ for high availability.
    Default is true (single NAT gateway).
  EOT
  default     = true
}

variable "nat_gateway_az" {
  type        = string
  description = "Availability zone for the NAT gateway when single_nat_gateway=true. Defaults to first public subnet AZ if not specified."
  default     = null
}

variable "map_public_ip_on_launch" {
  type        = bool
  description = "Auto-assign public IP to instances launched in public subnets"
  default     = false
}

variable "public_subnet_tags" {
  type        = map(string)
  description = "Additional tags to apply to public subnets (e.g., Kubernetes ELB discovery tags)"
  default     = {}
}

variable "private_subnet_tags" {
  type        = map(string)
  description = "Additional tags to apply to private subnets (e.g., Kubernetes internal ELB discovery tags)"
  default     = {}
}

# =============================================================================
# VPN Gateway Variables
# =============================================================================

variable "enable_vpn_gateway" {
  type        = bool
  description = "Create a VPN gateway attached to this VPC"
  default     = false
}

variable "vpn_gateway_id" {
  type        = string
  description = "ID of an existing VPN gateway to attach to the VPC (instead of creating a new one)"
  default     = ""
}

variable "amazon_side_asn" {
  type        = number
  description = "The Autonomous System Number (ASN) for the Amazon side of the gateway. Default is the AWS default ASN."
  default     = 64512
}

variable "vpn_gateway_tags" {
  type        = map(string)
  description = "Additional tags for the VPN gateway"
  default     = {}
}

variable "propagate_public_route_tables_vgw" {
  type        = bool
  description = "Propagate VPN gateway routes to the public route table"
  default     = false
}

variable "propagate_private_route_tables_vgw" {
  type        = bool
  description = "Propagate VPN gateway routes to the private route table"
  default     = false
}

# =============================================================================
# Flow Logs Variables
# =============================================================================

variable "do_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs delivered to S3"
  default     = false
}

variable "flow_logs_destination_arn" {
  type        = string
  description = "ARN of an existing S3 bucket (optionally with a /prefix) for flow logs. If null, the module creates a bucket."
  default     = null
}

variable "flow_logs_traffic_type" {
  type        = string
  description = "Type of traffic to capture in flow logs: ACCEPT, REJECT, or ALL"
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be one of ACCEPT, REJECT, or ALL."
  }
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Days to keep flow logs in the module-created bucket before they expire (0 = keep forever)"
  default     = 90

  validation {
    condition     = var.flow_logs_retention_days >= 0
    error_message = "flow_logs_retention_days must be 0 or greater."
  }
}

variable "flow_logs_bucket_force_destroy" {
  type        = bool
  description = "Allow the module-created flow logs bucket to be destroyed even if it contains objects"
  default     = false
}