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
      gateway_id         = aws_dx_gateway.this[0].id
      aws_side_asn       = aws_dx_gateway.this[0].amazon_side_asn
      virtual_interfaces = concat(aws_dx_transit_virtual_interface.first[*].id, aws_dx_transit_virtual_interface.second[*].id)
    }
    advertised_prefixes = local.advertised_prefixes
    expected_prefixes   = local.network.onprem_cidrs
  }
}
