locals {
  segments      = local.network.segments
  address_space = local.network.address_space
  central       = local.network.egress_mode == "central"

  blocks   = try(data.terraform_remote_state.ipam.outputs.regional_blocks[local.region], null)
  pool_ids = try(data.terraform_remote_state.ipam.outputs.regional_pool_ids[local.region], null)

  # Each segment table drops the other segment, so a cross-segment packet
  # never takes the default route (egress, a peering) and comes back through
  # shared. Every table drops the rest of address_space (reserved block, a
  # region not peered yet): without it, central mode would loop such a packet
  # through the egress VPC. Propagated and static routes are more specific
  # and win.
  blackholes = merge(
    {
      "production/${local.segments["non-production"]}" = { table = "production", cidr = local.segments["non-production"] }
      "non-production/${local.segments.production}"    = { table = "non-production", cidr = local.segments.production }
    },
    { for t in keys(local.segments) : "${t}/${local.address_space}" => { table = t, cidr = local.address_space } },
  )

  egress_azs = try(local.spec.egress_azs, slice(data.aws_availability_zones.this.names, 0, 3))
}
