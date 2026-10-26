# dx_vpn and dual_dx: one Direct Connect gateway, a transit virtual interface
# on each of the adopter's connections (ordered by the adopter; IDs in the
# YAML), associated with the first hub's transit gateway, and with dual_dx the
# second hub's too. A virtual interface is created in its connection's region,
# hence one resource per hub.

resource "aws_dx_gateway" "this" {
  count = local.dx ? 1 : 0

  name            = "${local.name_prefix}-onprem"
  amazon_side_asn = tostring(local.settings.dx_gateway_asn)

  depends_on = [terraform_data.validation]
}

resource "aws_dx_transit_virtual_interface" "first" {
  count = local.dx ? 1 : 0

  name             = "${local.name_prefix}-onprem-1"
  connection_id    = local.connections[0].connection_id
  dx_gateway_id    = aws_dx_gateway.this[0].id
  vlan             = local.connections[0].vlan
  bgp_asn          = local.connections[0].bgp_asn
  address_family   = "ipv4"
  amazon_address   = try(local.connections[0].amazon_address, null)
  customer_address = try(local.connections[0].customer_address, null)
  bgp_auth_key     = try(local.connections[0].bgp_auth_key, null)
}

resource "aws_dx_transit_virtual_interface" "second" {
  provider = aws.second
  count    = local.dual_dx ? 1 : 0

  name             = "${local.name_prefix}-onprem-2"
  connection_id    = local.connections[1].connection_id
  dx_gateway_id    = aws_dx_gateway.this[0].id
  vlan             = local.connections[1].vlan
  bgp_asn          = local.connections[1].bgp_asn
  address_family   = "ipv4"
  amazon_address   = try(local.connections[1].amazon_address, null)
  customer_address = try(local.connections[1].customer_address, null)
  bgp_auth_key     = try(local.connections[1].bgp_auth_key, null)
}

# Allowed prefixes: the three segment summaries, so on-prem learns production,
# non-production and shared. With dual_dx both associations advertise the
# same summaries; verify at first real apply that the gateway accepts that,
# else advertise each hub's own regional blocks (see README).
resource "aws_dx_gateway_association" "first" {
  count = local.dx ? 1 : 0

  dx_gateway_id         = aws_dx_gateway.this[0].id
  associated_gateway_id = local.first.transit_gateway_id
  allowed_prefixes      = local.advertised_prefixes
}

resource "aws_dx_gateway_association" "second" {
  provider = aws.second
  count    = local.dual_dx ? 1 : 0

  dx_gateway_id         = aws_dx_gateway.this[0].id
  associated_gateway_id = local.second.transit_gateway_id
  allowed_prefixes      = local.advertised_prefixes
}

resource "aws_ec2_transit_gateway_route_table_association" "dx_first" {
  count = local.dx ? 1 : 0

  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.first[0].id
  transit_gateway_route_table_id = local.first.route_table_ids.shared
}

resource "aws_ec2_transit_gateway_route_table_propagation" "dx_first" {
  for_each = local.dx ? local.network.segments : {}

  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.first[0].id
  transit_gateway_route_table_id = local.first.route_table_ids[each.key]
}

resource "aws_ec2_transit_gateway_route_table_association" "dx_second" {
  provider = aws.second
  count    = local.dual_dx ? 1 : 0

  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.second[0].id
  transit_gateway_route_table_id = local.second.route_table_ids.shared
}

resource "aws_ec2_transit_gateway_route_table_propagation" "dx_second" {
  provider = aws.second
  for_each = local.dual_dx ? local.network.segments : {}

  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.second[0].id
  transit_gateway_route_table_id = local.second.route_table_ids[each.key]
}
