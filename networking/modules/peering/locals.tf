locals {
  peer_region = module.context.instance

  local_side = try(data.terraform_remote_state.local.outputs, {})
  peer_side  = try(data.terraform_remote_state.peer.outputs, {})
  ready      = alltrue([for s in [local.local_side, local.peer_side] : try(s.transit_gateway_id, null) != null && try(s.blocks, null) != null])

  first_hub = local.network.first_hub

  # Peering propagates nothing: each side routes the other's blocks by
  # segment. A segment table only ever gets the same segment's block; shared
  # gets all three.
  #
  # Every region other than the first hub (the second hub included) also
  # routes, from production and non-production, the first hub's shared block
  # (tooling VPC, hub DNS) and on-prem through its peering with the first
  # hub: on-prem attaches only there (with dual_dx, one Direct Connect gateway
  # carrying both connections).
  sides = {
    local = { region = local.region, other_region = local.peer_region, other = local.peer_side }
    peer  = { region = local.peer_region, other_region = local.region, other = local.local_side }
  }

  routes = { for side, s in local.sides : side => !local.ready ? {} : merge(
    {
      "production/${s.other.blocks.production}"            = { table = "production", cidr = s.other.blocks.production }
      "non-production/${s.other.blocks["non-production"]}" = { table = "non-production", cidr = s.other.blocks["non-production"] }
    },
    { for seg, cidr in s.other.blocks : "shared/${cidr}" => { table = "shared", cidr = cidr } },
    s.other_region != local.first_hub || s.region == local.first_hub ? {} : merge(
      { for t in ["production", "non-production"] : "${t}/${s.other.blocks.shared}" => { table = t, cidr = s.other.blocks.shared } },
      {
        for pair in setproduct(["production", "non-production"], local.network.onprem_cidrs) :
        "${pair[0]}/${pair[1]}" => { table = pair[0], cidr = pair[1] }
      },
    ),
  ) }
}
