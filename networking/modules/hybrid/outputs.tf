# The handoff to the on-prem team: `terraform output onprem`.
output "onprem" {
  description = "What the on-prem side must configure: VPN tunnels, Direct Connect, prefixes advertised and expected."
  value = {
    mode = local.mode
    vpn = !local.vpn ? null : {
      aws_side_asn = local.first.amazon_side_asn
      tunnels = [for i in [1, 2] : {
        outside_address   = aws_vpn_connection.this[0]["tunnel${i}_address"]
        aws_inside_ip     = aws_vpn_connection.this[0]["tunnel${i}_vgw_inside_address"]
        onprem_inside_ip  = aws_vpn_connection.this[0]["tunnel${i}_cgw_inside_address"]
        inside_cidr       = aws_vpn_connection.this[0]["tunnel${i}_inside_cidr"]
        preshared_key_ref = "aws ec2 describe-vpn-connections --vpn-connection-ids ${aws_vpn_connection.this[0].id}"
      }]
    }
    dx = !local.dx ? null : {
      connections = [for i, c in local.connections : {
        hub               = local.network.hub_regions[i]
        connection_id     = c.connection_id
        gateway_id        = [aws_dx_gateway.first, aws_dx_gateway.second][i][0].id
        aws_side_asn      = [aws_dx_gateway.first, aws_dx_gateway.second][i][0].amazon_side_asn
        virtual_interface = [aws_dx_transit_virtual_interface.first, aws_dx_transit_virtual_interface.second][i][0].id
      }]
      # AWS to on-prem is fixed by region: the second hub's region over its own
      # connection, every other region over the first hub's (static routes
      # through the peering; peering propagates nothing). On-prem should send
      # over the same connection: prefer the primary for everything except the
      # second hub's blocks, or keep its edge stateless across both.
      primary   = { hub = local.network.first_hub, connection_id = local.connections[0].connection_id }
      secondary = !local.dual_dx ? null : { hub = local.second_hub, connection_id = local.connections[1].connection_id, serves = local.second_hub }
    }
    advertised_prefixes = local.advertised_prefixes
    expected_prefixes   = local.network.onprem_cidrs
  }
}
