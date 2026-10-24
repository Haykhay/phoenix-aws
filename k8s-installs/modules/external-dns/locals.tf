locals {
  defaults = {
    enabled       = true
    chart_version = "1.21.1"
    app_version   = ""
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace            = "external-dns"
  service_account_name = "external-dns"
  role_name            = "${local.name_prefix}-external-dns"

  # Owner of the TXT records it writes: cluster-unique, so two clusters in one
  # environment never take over each other's records.
  txt_owner_id = coalesce(try(local.config.settings.txt_owner_id, null), local.name_prefix)

  # The cluster's own zone by default; naming zone keys widens both what it
  # reconciles and what its IAM policy allows.
  zone_keys = try(local.config.settings.providers.route53.zones, [])
  route53_zone_ids = length(local.zone_keys) > 0 ? flatten([
    for key in local.zone_keys : [
      module.cluster.dns_zones[key].public_zone_id,
      module.cluster.dns_zones[key].internal_zone_id,
    ]
  ]) : compact([try(module.cluster.dns.public_zone_id, null), try(module.cluster.dns.internal_zone_id, null)])
}
