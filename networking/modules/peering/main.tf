# Requested from this region, accepted in the peer. Never removed
# automatically: other regions' traffic may ride it.
resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  transit_gateway_id      = local.local_side.transit_gateway_id
  peer_transit_gateway_id = local.peer_side.transit_gateway_id
  peer_region             = local.peer_region
  peer_account_id         = local.account_id

  tags = {
    Name = "${local.name_prefix}-to-${local.peer_region}"
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = local.peer_region != null && local.peer_region != local.region
      error_message = "The unit file must be <region>/peering.<peer region>.yaml, with a peer other than ${local.region}."
    }
    precondition {
      condition     = local.ready
      error_message = "Apply the region unit in both ${local.region} and ${coalesce(local.peer_region, "the peer")} before peering them."
    }
  }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  provider = aws.peer

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this.id

  tags = {
    Name = "${local.name_prefix}-to-${local.peer_region}"
  }
}

# Traffic arriving over the peering is looked up in shared, which routes to
# every local VPC: the sending side's segment table already decided what may
# leave.
resource "aws_ec2_transit_gateway_route_table_association" "local" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this.id
  transit_gateway_route_table_id = local.local_side.route_table_ids.shared

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.this]
}

resource "aws_ec2_transit_gateway_route_table_association" "peer" {
  provider = aws.peer

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.this.transit_gateway_attachment_id
  transit_gateway_route_table_id = local.peer_side.route_table_ids.shared
}

resource "aws_ec2_transit_gateway_route" "local" {
  for_each = local.routes.local

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this.id
  transit_gateway_route_table_id = local.local_side.route_table_ids[each.value.table]

  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.this]
}

resource "aws_ec2_transit_gateway_route" "peer" {
  provider = aws.peer
  for_each = local.routes.peer

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.this.transit_gateway_attachment_id
  transit_gateway_route_table_id = local.peer_side.route_table_ids[each.value.table]
}
