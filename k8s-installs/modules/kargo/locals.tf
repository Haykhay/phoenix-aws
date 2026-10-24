locals {
  defaults = {
    enabled       = true
    chart_version = "1.11.2"
    app_version   = ""
    # The environment's cluster running the full Kargo; every other cluster
    # in the environment runs a shard controller (spoke) reporting to it.
    management_cluster = "1"
    settings           = {}
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "kargo"

  management_cluster = tostring(local.config.management_cluster)
  mode               = local.cluster_key == local.management_cluster ? "management" : "spoke"
  is_management      = local.config.enabled && local.mode == "management"
  is_spoke           = local.config.enabled && local.mode == "spoke"

  shard       = "${local.environment}-${local.cluster_key}"
  secret_path = "${local.organisation}/${local.environment}/kargo"

  dns      = module.cluster.dns
  api_host = "kargo.${try(local.dns.internal_zone_name, "dns-missing")}"

  # Argo CD per cluster (argo-cd unit), for UI deep links.
  argocd_urls = merge(
    { (local.shard) = "https://argocd-${local.cluster_key}.${try(local.dns.internal_zone_name, "dns-missing")}" },
    try(local.config.settings.argocd_urls, {}),
  )
}
