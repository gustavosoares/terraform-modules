# =============================================================================
# Required Variables
# =============================================================================

variable "name" {
  type        = string
  description = "Name for the instance (Name tag) and prefix for related resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the instance and its security group are created"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the instance"
}

# =============================================================================
# Instance
# =============================================================================

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "ami" {
  type        = string
  description = "AMI ID. If null, the latest Amazon Linux 2023 x86_64 AMI at creation time is used (later AMI releases do not replace the instance)."
  default     = null
}

variable "user_data" {
  type        = string
  description = "User data script to run on instance launch"
  default     = null
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GiB (gp3, encrypted)"
  default     = 8
}

variable "iam_policy_arns" {
  type        = list(string)
  description = "Managed IAM policy ARNs to attach to the instance role (e.g. AmazonSSMManagedInstanceCore)"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}

# =============================================================================
# Security Group
# =============================================================================

variable "ingress_rules" {
  type = list(object({
    description                  = string
    port                         = optional(number)
    to_port                      = optional(number)
    protocol                     = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  description = <<-EOT
    Ingress rules for the instance security group. Each rule needs exactly one source:
    cidr_ipv4 or referenced_security_group_id. port is the start of the range; to_port
    defaults to port. Use protocol "-1" for all traffic (ports are ignored).
  EOT
  default     = []

  validation {
    condition = alltrue([
      for r in var.ingress_rules :
      (r.cidr_ipv4 != null) != (r.referenced_security_group_id != null) && (r.protocol == "-1" || r.port != null)
    ])
    error_message = "Each ingress rule needs exactly one of cidr_ipv4 or referenced_security_group_id, and a port unless protocol is \"-1\"."
  }
}

variable "egress_rules" {
  type = list(object({
    description                  = string
    port                         = optional(number)
    to_port                      = optional(number)
    protocol                     = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  description = <<-EOT
    Egress rules for the instance security group (same shape as ingress_rules).
    With no egress rules the instance has NO outbound access. SSM, package
    installs, and AWS API calls need at least HTTPS (443) outbound.
  EOT
  default     = []

  validation {
    condition = alltrue([
      for r in var.egress_rules :
      (r.cidr_ipv4 != null) != (r.referenced_security_group_id != null) && (r.protocol == "-1" || r.port != null)
    ])
    error_message = "Each egress rule needs exactly one of cidr_ipv4 or referenced_security_group_id, and a port unless protocol is \"-1\"."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs to attach to the instance"
  default     = []
}

# =============================================================================
# Schedule
# =============================================================================

variable "schedule" {
  type = object({
    stop     = string
    start    = string
    timezone = optional(string, "UTC")
  })
  description = "EventBridge Scheduler expressions to stop and start the instance (e.g. stop = \"cron(0 20 ? * MON-FRI *)\"). Null disables scheduling."
  default     = null
}
