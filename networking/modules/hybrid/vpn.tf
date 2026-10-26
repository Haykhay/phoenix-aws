# vpn, and the backup for dx_vpn: one site-to-site VPN (two IPsec tunnels,
# BGP) on the first hub's transit gateway. With dx_vpn, AWS prefers Direct
# Connect over VPN for the same prefixes.

resource "aws_customer_gateway" "this" {
  count = local.vpn ? 1 : 0

  bgp_asn    = tostring(local.settings.customer_gateway.bgp_asn)
  ip_address = local.settings.customer_gateway.ip
  type       = "ipsec.1"

  tags = {
    Name = "${local.name_prefix}-onprem"
  }

  depends_on = [terraform_data.validation]
}

resource "aws_vpn_connection" "this" {
  count = local.vpn ? 1 : 0

  customer_gateway_id = aws_customer_gateway.this[0].id
  transit_gateway_id  = local.first.transit_gateway_id
  type                = "ipsec.1"
  static_routes_only  = false

  tags = {
    Name = "${local.name_prefix}-onprem"
  }
}

# On-prem sits in shared: it reaches both segments and both reach it. Which
# on-prem networks may talk to which segment is the adopter's edge firewall.
resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  count = local.vpn ? 1 : 0

  transit_gateway_attachment_id  = aws_vpn_connection.this[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = local.first.route_table_ids.shared
}

resource "aws_ec2_transit_gateway_route_table_propagation" "vpn" {
  for_each = local.vpn ? local.network.segments : {}

  transit_gateway_attachment_id  = aws_vpn_connection.this[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = local.first.route_table_ids[each.key]
}
