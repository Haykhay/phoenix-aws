# Never removed automatically, even when the region's last environment goes.
resource "aws_ec2_transit_gateway" "this" {
  description     = "${local.name_prefix}-tgw"
  amazon_side_asn = try(local.spec.amazon_side_asn, 64512)

  # Every association and propagation is explicit, made by Terraform from the
  # networking account; attachments from shared accounts need no acceptance.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = {
    Name = "${local.name_prefix}-tgw"
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = local.blocks != null && local.pool_ids != null
      error_message = "${local.region} has not joined IPAM: add it to networking/environments/global/ipam.yaml regions and apply ipam first."
    }
  }
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = local.segments

  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = {
    Name    = "${local.name_prefix}-${each.key}"
    Segment = each.key
  }
}

resource "aws_ec2_transit_gateway_route" "blackhole" {
  for_each = local.blackholes

  destination_cidr_block         = each.value.cidr
  blackhole                      = true
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.table].id
}

# Group accounts attach their VPCs; the attachments are auto-accepted.
resource "aws_ram_resource_share" "tgw" {
  name                      = "${local.name_prefix}-tgw"
  allow_external_principals = false

  tags = {
    Name = "${local.name_prefix}-tgw"
  }
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "tgw" {
  for_each = toset(local.network.share_with)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
