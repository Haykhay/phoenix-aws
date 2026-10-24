locals {
  defaults = {
    enabled       = true
    chart_version = "3.4.0"
    app_version   = ""
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  role_name            = "${local.name_prefix}-aws-load-balancer-controller"

  # Load balancers it creates carry the unit's tags, like every other resource.
  default_tags = merge(module.context.tags, { Cluster = local.cluster_key })
}
