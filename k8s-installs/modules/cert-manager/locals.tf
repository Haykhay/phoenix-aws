locals {
  defaults = {
    enabled       = true
    chart_version = "v1.20.2"
    app_version   = ""
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace            = "cert-manager"
  service_account_name = "cert-manager"
  role_name            = "${local.name_prefix}-cert-manager"

  install_crds = try(local.config.settings.install_crds, true)
  # Optional: Let's Encrypt no longer needs an account email.
  acme_email = try(local.config.settings.acme_email, "")
  # Off: certificates are explicit Certificate resources (istio's wildcards),
  # and with it on cert-manager will not start until istio's Gateway API CRDs
  # exist — while istio itself waits for cert-manager.
  enable_gateway_api = try(local.config.settings.enable_gateway_api, false)

  dns = module.cluster.dns
  hosted_zone_arns = coalesce(try(local.config.settings.hosted_zone_arns, null), [
    "arn:aws:route53:::hostedzone/${try(local.dns.public_zone_id, "dns-missing")}",
    "arn:aws:route53:::hostedzone/${try(local.dns.internal_zone_id, "dns-missing")}",
  ])
}
