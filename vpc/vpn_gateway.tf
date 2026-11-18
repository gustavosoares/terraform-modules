# =============================================================================
# VPN Gateway (optional)
# =============================================================================

resource "aws_vpn_gateway" "main" {
  count = var.enable_vpn_gateway ? 1 : 0

  vpc_id          = aws_vpc.main.id
  amazon_side_asn = var.amazon_side_asn

  tags = merge(var.tags, var.vpn_gateway_tags, {
    Name = "${var.name_prefix}-vgw"
  })
}

resource "aws_vpn_gateway_attachment" "main" {
  count = var.vpn_gateway_id != "" ? 1 : 0

  vpc_id         = aws_vpc.main.id
  vpn_gateway_id = var.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "public" {
  count = var.propagate_public_route_tables_vgw && (var.enable_vpn_gateway || var.vpn_gateway_id != "") ? 1 : 0

  route_table_id = aws_route_table.public.id
  vpn_gateway_id = var.enable_vpn_gateway ? aws_vpn_gateway.main[0].id : var.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "private" {
  for_each = var.propagate_private_route_tables_vgw && (var.enable_vpn_gateway || var.vpn_gateway_id != "") ? aws_route_table.private : {}

  route_table_id = each.value.id
  vpn_gateway_id = var.enable_vpn_gateway ? aws_vpn_gateway.main[0].id : var.vpn_gateway_id
}

