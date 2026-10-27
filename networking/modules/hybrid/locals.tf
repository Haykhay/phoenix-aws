locals {
  mode     = local.network.hybrid
  vpn      = contains(["vpn", "dx_vpn"], local.mode)
  dx       = contains(["dx_vpn", "dual_dx"], local.mode)
  dual_dx  = local.mode == "dual_dx"
  settings = try(local.spec.hybrid_settings, {})


  first = try(data.terraform_remote_state.first.outputs, {})

  connections = try(local.settings.connections, [])

  # On-prem learns the three segment summaries; AWS expects onprem_cidrs back.
  advertised_prefixes = values(local.network.segments)
}
