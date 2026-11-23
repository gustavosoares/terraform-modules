# VPC Module

A minimal Terraform module for creating a VPC with public and private subnets, suitable for bootstrapping new environments.

## Features

- VPC with configurable CIDR block
- Public subnets with Internet Gateway access
- Private subnets with optional NAT Gateway for outbound internet access
- **Single or per-AZ NAT gateways** for cost optimization or high availability
- Optional VPN Gateway with route propagation support
- Optional VPC Flow Logs to S3 (module-managed bucket or existing destination)
- Flexible availability zone configuration
- Configurable tags for all resources

## Usage

### Basic Example

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "10.0.0.0/16"
  vpc_name       = "my-vpc"
  name_prefix    = "myapp"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
    "us-east-1b" = "10.0.102.0/24"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### Different Region Example (us-west-2)

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "172.20.0.0/16"
  vpc_name       = "example-dev"
  name_prefix    = "example"

  public_subnets = {
    "us-west-2a" = "172.20.0.0/24"
    "us-west-2b" = "172.20.1.0/24"
  }

  private_subnets = {
    "us-west-2a" = "172.20.100.0/24"
    "us-west-2b" = "172.20.101.0/24"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### With VPC Flow Logs

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "10.0.0.0/16"
  vpc_name       = "logged-vpc"
  name_prefix    = "logged"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
  }

  # Creates an encrypted, private S3 bucket and sends flow logs to it
  do_flow_logs             = true
  flow_logs_retention_days = 30

  # Or send to an existing bucket instead:
  # flow_logs_destination_arn = "arn:aws:s3:::my-central-logs-bucket/vpc-flow-logs"
}
```

### Without NAT Gateway (cost savings for dev/test)

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block     = "10.0.0.0/16"
  vpc_name           = "test-vpc"
  name_prefix        = "test"
  enable_nat_gateway = false  # Private subnets won't have internet access

  public_subnets = {
    "us-west-2a" = "10.0.1.0/24"
  }

  private_subnets = {
    "us-west-2a" = "10.0.101.0/24"
  }
}
```

### High Availability NAT (one per AZ)

For production environments where you need high availability and want to avoid cross-AZ traffic charges:

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "10.0.0.0/16"
  vpc_name       = "prod-ha-vpc"
  name_prefix    = "prod"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
    "us-east-1c" = "10.0.3.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
    "us-east-1b" = "10.0.102.0/24"
    "us-east-1c" = "10.0.103.0/24"
  }

  # Create one NAT gateway per AZ for high availability
  single_nat_gateway = false
}
```

**NAT Gateway Options:**

| Option | `single_nat_gateway` | Cost | Availability | Use Case |
|--------|---------------------|------|--------------|----------|
| Single NAT | `true` (default) | ~$32/month | Single point of failure | Dev/Test, cost-sensitive |
| NAT per AZ | `false` | ~$32/month × AZs | Highly available | Production |

NAT gateways live in public subnets, so `nat_gateway_az` must be one of the `public_subnets` AZs, and with `single_nat_gateway = false` every `private_subnets` AZ needs a public subnet too. The module checks both at plan time.

### Three Availability Zones

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "10.0.0.0/16"
  vpc_name       = "prod-vpc"
  name_prefix    = "prod"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
    "us-east-1c" = "10.0.3.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
    "us-east-1b" = "10.0.102.0/24"
    "us-east-1c" = "10.0.103.0/24"
  }

  nat_gateway_az = "us-east-1a"  # Specify which AZ hosts the NAT gateway
}
```

### With VPN Gateway

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "10.0.0.0/16"
  vpc_name       = "vpn-vpc"
  name_prefix    = "vpn"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
    "us-east-1b" = "10.0.102.0/24"
  }

  # Create a new VPN gateway
  enable_vpn_gateway                 = true
  amazon_side_asn                    = 65000
  propagate_private_route_tables_vgw = true  # Propagate VPN routes to private subnets

  vpn_gateway_tags = {
    Purpose = "site-to-site-vpn"
  }
}
```

### Attach Existing VPN Gateway

```hcl
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "10.0.0.0/16"
  vpc_name       = "existing-vpn-vpc"
  name_prefix    = "existing"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
  }

  # Attach an existing VPN gateway instead of creating a new one
  vpn_gateway_id                     = "vgw-12345678"
  propagate_private_route_tables_vgw = true
  propagate_public_route_tables_vgw  = false
}
```

### With Kubernetes/EKS Subnet Tags

For EKS clusters, subnets need specific tags for the AWS Load Balancer Controller to discover them:

```hcl
locals {
  cluster_name = "my-eks-cluster"
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr_block = "10.0.0.0/16"
  vpc_name       = "eks-vpc"
  name_prefix    = "eks"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
    "us-east-1b" = "10.0.102.0/24"
  }

  # Tags for AWS Load Balancer Controller to discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${local.cluster_name}"       = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/${local.cluster_name}"       = "shared"
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Defining Availability Zones

Subnets are defined using a map where:
- **Key** = Availability Zone name (e.g., `us-east-1a`, `us-west-2b`)
- **Value** = CIDR block for that subnet

```hcl
# Format: { "az-name" = "cidr-block" }
public_subnets = {
  "us-east-1a" = "10.0.1.0/24"   # AZ 'a' gets this CIDR
  "us-east-1b" = "10.0.2.0/24"   # AZ 'b' gets this CIDR
}
```

### Subnet CIDR Planning

When planning your subnet CIDRs, consider:

1. **VPC CIDR size**: A `/16` gives you 65,536 IPs
2. **Subnet size**: A `/24` gives you 251 usable IPs (AWS reserves 5)
3. **Leave room for growth**: Don't use the entire VPC CIDR immediately

**Example allocation for a `/16` VPC:**

| Subnet Type | AZ | CIDR Block | IP Range |
|-------------|-----|------------|----------|
| Public | a | x.x.0.0/24 | x.x.0.1 - x.x.0.254 |
| Public | b | x.x.1.0/24 | x.x.1.1 - x.x.1.254 |
| Public | c | x.x.2.0/24 | x.x.2.1 - x.x.2.254 |
| Private | a | x.x.100.0/24 | x.x.100.1 - x.x.100.254 |
| Private | b | x.x.101.0/24 | x.x.101.1 - x.x.101.254 |
| Private | c | x.x.102.0/24 | x.x.102.1 - x.x.102.254 |
| *Reserved* | - | x.x.200.0/24+ | Future use |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `vpc_cidr_block` | CIDR block for the VPC | `string` | - | yes |
| `public_subnets` | Map of AZ to CIDR for public subnets | `map(string)` | - | yes |
| `private_subnets` | Map of AZ to CIDR for private subnets | `map(string)` | - | yes |
| `vpc_name` | Name tag for the VPC | `string` | `"simple-vpc"` | no |
| `name_prefix` | Prefix for resource names | `string` | `"simple"` | no |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` | no |
| `enable_dns_hostnames` | Enable DNS hostnames in VPC | `bool` | `true` | no |
| `enable_dns_support` | Enable DNS support in VPC | `bool` | `true` | no |
| `enable_nat_gateway` | Create NAT gateway(s) for private subnets | `bool` | `true` | no |
| `single_nat_gateway` | Use single NAT gateway (true) or one per AZ (false) | `bool` | `true` | no |
| `nat_gateway_az` | AZ for NAT gateway when single_nat_gateway=true | `string` | `null` | no |
| `map_public_ip_on_launch` | Auto-assign public IPs in public subnets | `bool` | `false` | no |
| `public_subnet_tags` | Additional tags to apply to public subnets (e.g., Kubernetes ELB tags) | `map(string)` | `{}` | no |
| `private_subnet_tags` | Additional tags to apply to private subnets (e.g., Kubernetes internal ELB tags) | `map(string)` | `{}` | no |
| `enable_vpn_gateway` | Create a VPN gateway attached to this VPC | `bool` | `false` | no |
| `vpn_gateway_id` | ID of an existing VPN gateway to attach (instead of creating new) | `string` | `""` | no |
| `amazon_side_asn` | Amazon side ASN for the VPN gateway | `number` | `64512` | no |
| `vpn_gateway_tags` | Additional tags for the VPN gateway | `map(string)` | `{}` | no |
| `propagate_public_route_tables_vgw` | Propagate VPN routes to public route table | `bool` | `false` | no |
| `propagate_private_route_tables_vgw` | Propagate VPN routes to private route table | `bool` | `false` | no |
| `do_flow_logs` | Enable VPC flow logs delivered to S3 | `bool` | `false` | no |
| `flow_logs_destination_arn` | Existing S3 bucket ARN for flow logs; if null, a bucket is created | `string` | `null` | no |
| `flow_logs_traffic_type` | Traffic to capture: `ACCEPT`, `REJECT`, or `ALL` | `string` | `"ALL"` | no |
| `flow_logs_retention_days` | Expiration for logs in the module-created bucket (0 = never) | `number` | `90` | no |
| `flow_logs_bucket_force_destroy` | Allow destroying the module-created bucket when non-empty | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC |
| `vpc_cidr_block` | CIDR block of the VPC |
| `vpc_arn` | ARN of the VPC |
| `public_subnet_ids` | List of public subnet IDs |
| `public_subnet_cidr_blocks` | List of public subnet CIDR blocks |
| `public_subnets_by_az` | Map of AZ to public subnet ID |
| `private_subnet_ids` | List of private subnet IDs |
| `private_subnet_cidr_blocks` | List of private subnet CIDR blocks |
| `private_subnets_by_az` | Map of AZ to private subnet ID |
| `internet_gateway_id` | ID of the Internet Gateway |
| `nat_gateway_id` | ID of the NAT Gateway (first one if multiple) |
| `nat_gateway_ids` | List of all NAT Gateway IDs |
| `nat_gateways_by_az` | Map of AZ to NAT Gateway ID |
| `nat_gateway_public_ip` | Public IP of the NAT Gateway (first one if multiple) |
| `nat_gateway_public_ips` | List of all NAT Gateway public IPs |
| `public_route_table_id` | ID of the public route table |
| `private_route_table_id` | ID of the private route table (first one if multiple) |
| `private_route_table_ids` | List of all private route table IDs |
| `private_route_tables_by_az` | Map of AZ (or 'shared') to private route table ID |
| `availability_zones` | List of AZs used |
| `vpn_gateway_id` | ID of the VPN Gateway (null if disabled) |
| `vpn_gateway_arn` | ARN of the VPN Gateway (null if disabled or using external gateway) |
| `flow_log_id` | ID of the VPC flow log (null if disabled) |
| `flow_logs_bucket_arn` | ARN of the module-created flow logs bucket (null if disabled or using an existing destination) |

## When to Use This Module

**This module is a good fit when:**
- Bootstrapping a new environment
- Creating a standalone VPC
- You need a minimal network setup quickly

**Out of scope (compose with other modules/resources):**
- VPC peering or Transit Gateway attachments
- IPv6 support
- Route53 hosted zones
- VPC endpoints

## Architecture

### Single NAT Gateway (default, `single_nat_gateway = true`)

```
┌─────────────────────────────────────────────────────────────────┐
│                            VPC                                   │
│                     (vpc_cidr_block)                            │
│                                                                  │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │   Public Subnet A   │    │   Public Subnet B   │            │
│  │   (public_subnets)  │    │   (public_subnets)  │            │
│  │         │           │    │                     │            │
│  └─────────┼───────────┘    └─────────────────────┘            │
│            │                                                    │
│            └──────────┬─────────────────────────────────────    │
│                       │                                         │
│              ┌────────▼────────┐                               │
│              │ Internet Gateway │◄────────► Internet            │
│              └────────┬────────┘                               │
│                       │                                         │
│              ┌────────▼────────┐                               │
│              │   NAT Gateway   │ (single, in AZ-A)             │
│              └────────┬────────┘                               │
│                       │                                         │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │  Private Subnet A   │    │  Private Subnet B   │            │
│  │  (private_subnets)  │    │  (private_subnets)  │            │
│  │  [EC2, ECS, RDS]────┼────┼──► uses same NAT    │            │
│  └─────────────────────┘    └─────────────────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### High Availability NAT (`single_nat_gateway = false`)

```
┌─────────────────────────────────────────────────────────────────┐
│                            VPC                                   │
│                     (vpc_cidr_block)                            │
│                                                                  │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │   Public Subnet A   │    │   Public Subnet B   │            │
│  │         │           │    │         │           │            │
│  │  ┌──────▼──────┐    │    │  ┌──────▼──────┐    │            │
│  │  │ NAT GW (A)  │    │    │  │ NAT GW (B)  │    │            │
│  │  └──────┬──────┘    │    │  └──────┬──────┘    │            │
│  └─────────┼───────────┘    └─────────┼───────────┘            │
│            │                          │                         │
│            └──────────┬───────────────┘                         │
│                       │                                         │
│              ┌────────▼────────┐                               │
│              │ Internet Gateway │◄────────► Internet            │
│              └─────────────────┘                               │
│                                                                  │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │  Private Subnet A   │    │  Private Subnet B   │            │
│  │         │           │    │         │           │            │
│  │    uses NAT (A)     │    │    uses NAT (B)     │            │
│  │  [EC2, ECS, RDS]    │    │  [EC2, ECS, RDS]    │            │
│  └─────────────────────┘    └─────────────────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

