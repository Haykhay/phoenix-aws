output "gateways" {
  description = "Gateways HTTPRoutes attach to (parentRefs), with the zone their hostnames live in."
  value = {
    internal = local.internal_gateway.enabled ? { name = "istio-internal", namespace = local.namespace, domain = local.internal_zone_name } : null
    external = local.external_gateway.enabled ? { name = "istio-external", namespace = local.namespace, domain = local.public_zone_name } : null
  }
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "istio"
    chart_version = local.config.chart_version
  }
}
