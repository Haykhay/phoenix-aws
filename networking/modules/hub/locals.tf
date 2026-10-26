locals {
  region_state = try(data.terraform_remote_state.region.outputs, {})
  ready        = try(local.region_state.transit_gateway_id, null) != null && try(local.region_state.pool_ids.shared, null) != null

  # Who may query the resolvers, and where the DNS VPC routes: the platform
  # and on-prem.
  dns_clients = concat([local.network.address_space], local.network.onprem_cidrs)

  forwarding = local.network.dns_forwarding
  forward    = length(local.forwarding) > 0

  dns_azs = try(local.spec.dns_azs, slice(data.aws_availability_zones.this.names, 0, 2))
}
