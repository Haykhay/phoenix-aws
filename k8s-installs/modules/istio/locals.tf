locals {
  defaults = {
    enabled       = true
    chart_version = "1.30.1"
    settings      = {}
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "istio-system"
  dns       = module.cluster.dns

  public_zone_name   = try(local.dns.public_zone_name, "dns-missing")
  internal_zone_name = try(local.dns.internal_zone_name, "dns-missing")

  public_secret_name   = "wildcard-istio-public-tls"
  internal_secret_name = "wildcard-istio-internal-tls"

  # Gateways get an NLB from aws-load-balancer-controller (IP targets).
  nlb_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
  }

  internal_gateway = {
    enabled = try(local.config.settings.gateways.internal.enabled, true)
    service_annotations = merge(
      local.nlb_annotations,
      { "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internal" },
      try(local.config.settings.gateways.internal.service_annotations, {}),
    )
  }

  external_gateway = {
    enabled = try(local.config.settings.gateways.external.enabled, false)
    service_annotations = merge(
      local.nlb_annotations,
      { "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing" },
      try(local.config.settings.gateways.external.service_annotations, {}),
    )
  }
}
