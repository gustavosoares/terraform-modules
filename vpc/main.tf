# VPC Module
# Creates a minimal VPC with public and private subnets, internet gateway, and NAT gateway

data "aws_caller_identity" "current" {}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id

  # Derive NAT gateway AZ from the first public subnet if not specified
  nat_gateway_az = var.nat_gateway_az != null ? var.nat_gateway_az : keys(var.public_subnets)[0]

  # Determine which AZs need NAT gateways (intersection of public and private subnet AZs)
  nat_gateway_azs = var.single_nat_gateway ? toset([local.nat_gateway_az]) : setintersection(keys(var.public_subnets), keys(var.private_subnets))

  # Map private subnet AZs to their NAT gateway AZ
  # When single_nat_gateway=true, all private subnets use the same NAT
  # When single_nat_gateway=false, each private subnet uses its own AZ's NAT
  private_subnet_nat_gateway_az = {
    for az in keys(var.private_subnets) :
    az => var.single_nat_gateway ? local.nat_gateway_az : az
  }
}

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(var.tags, {
    Name = var.vpc_name
  })

  # Checked here because every other resource depends on the VPC, so a bad
  # combination fails with a clear message instead of an index error later.
  lifecycle {
    precondition {
      condition     = !var.enable_nat_gateway || !var.single_nat_gateway || contains(keys(var.public_subnets), local.nat_gateway_az)
      error_message = "nat_gateway_az must be one of the public_subnets AZs, because the NAT gateway is placed in that AZ's public subnet."
    }

    precondition {
      condition     = !var.enable_nat_gateway || var.single_nat_gateway || length(setsubtract(keys(var.private_subnets), keys(var.public_subnets))) == 0
      error_message = "With single_nat_gateway = false, every private_subnets AZ needs a public subnet for its NAT gateway. Missing public subnets in: ${join(", ", sort(setsubtract(keys(var.private_subnets), keys(var.public_subnets))))}."
    }
  }
}

# =============================================================================
# Subnets
# =============================================================================

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, var.public_subnet_tags, {
    Name = "${var.name_prefix}-public-${each.key}"
    Type = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(var.tags, var.private_subnet_tags, {
    Name = "${var.name_prefix}-private-${each.key}"
    Type = "private"
  })
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# =============================================================================
# NAT Gateway (optional)
# =============================================================================

resource "aws_eip" "nat" {
  for_each = var.enable_nat_gateway ? local.nat_gateway_azs : toset([])

  tags = merge(var.tags, {
    Name = var.single_nat_gateway ? "${var.name_prefix}-nat-eip" : "${var.name_prefix}-nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "main" {
  for_each = var.enable_nat_gateway ? local.nat_gateway_azs : toset([])

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, {
    Name = var.single_nat_gateway ? "${var.name_prefix}-nat-gw" : "${var.name_prefix}-nat-gw-${each.key}"
  })

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# Route Tables - Public
# =============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# Route Tables - Private
# =============================================================================

# When single_nat_gateway=true: one shared route table for all private subnets
# When single_nat_gateway=false: one route table per AZ for HA
resource "aws_route_table" "private" {
  for_each = var.single_nat_gateway ? toset(["shared"]) : toset(keys(var.private_subnets))

  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = var.single_nat_gateway ? "${var.name_prefix}-rt-private" : "${var.name_prefix}-rt-private-${each.key}"
  })

  lifecycle {
    # When attaching VPN gateways it is common to define aws_vpn_gateway_route_propagation
    # resources that manipulate the attributes of the routing table (typically for the private subnets)
    ignore_changes = [propagating_vgws]
  }
}

resource "aws_route" "private_nat" {
  for_each = var.enable_nat_gateway ? aws_route_table.private : {}

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.main[local.nat_gateway_az].id : aws_nat_gateway.main[each.key].id
}

# Set the first private route table as the main/default route table for the VPC
resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.main.id
  route_table_id = var.single_nat_gateway ? aws_route_table.private["shared"].id : aws_route_table.private[keys(var.private_subnets)[0]].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = var.single_nat_gateway ? aws_route_table.private["shared"].id : aws_route_table.private[each.key].id
}
