resource "aws_vpc_ipam" "this" {
  description = "${local.name_prefix}-ipam"

  dynamic "operating_regions" {
    for_each = local.regions
    content {
      region_name = operating_regions.value
    }
  }

  tags = {
    Name = "${local.name_prefix}-ipam"
  }

  lifecycle {
    precondition {
      condition     = contains(local.regions, local.region)
      error_message = "spec.regions must include IPAM's home region ${local.region} (the YAML's global_region, the first hub)."
    }
  }
}

# One top pool per segment, holding the segment's whole block: the summary
# route everywhere the segment is used.
resource "aws_vpc_ipam_pool" "segment" {
  for_each = local.segments

  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  description    = each.key

  tags = {
    Name    = "${local.name_prefix}-${each.key}"
    Segment = each.key
  }
}

resource "aws_vpc_ipam_pool_cidr" "segment" {
  for_each = local.segments

  ipam_pool_id = aws_vpc_ipam_pool.segment[each.key].id
  cidr         = each.value
}

# A segment's share of a region is one block, so a peering needs one static
# route per segment per region. IPAM takes the first free block.
resource "aws_vpc_ipam_pool" "regional" {
  for_each = local.regional_pools

  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.segment[each.value.segment].id
  locale              = each.value.region
  description         = "${each.value.segment}/${each.value.region}"

  # Environment VPCs are /17 to /22. The shared segment also holds the
  # platform's own small VPCs (central egress, hub DNS: /24 by default).
  allocation_min_netmask_length = 17
  allocation_max_netmask_length = each.value.segment == "shared" ? 28 : 22

  tags = {
    Name    = "${local.name_prefix}-${each.value.segment}-${each.value.region}"
    Segment = each.value.segment
  }

  depends_on = [aws_vpc_ipam_pool_cidr.segment]
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each = local.regional_pools

  ipam_pool_id   = aws_vpc_ipam_pool.regional[each.key].id
  netmask_length = local.network.region_netmask

  # Freeing a region's block would let a new region reuse addresses that
  # routes, firewalls and on-prem still point at.
  lifecycle {
    prevent_destroy = true
  }
}

# Group accounts allocate VPCs from the regional pools.
resource "aws_ram_resource_share" "this" {
  name                      = "${local.name_prefix}-ipam-pools"
  allow_external_principals = false

  tags = {
    Name = "${local.name_prefix}-ipam-pools"
  }
}

resource "aws_ram_resource_association" "regional" {
  for_each = local.regional_pools

  resource_arn       = aws_vpc_ipam_pool.regional[each.key].arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_principal_association" "this" {
  for_each = toset(local.network.share_with)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this.arn
}
