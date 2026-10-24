locals {
  defaults = {
    enabled       = true
    chart_version = "1.14.0" # core-platform's controller policy covers up to 1.15
    # Default pool for everything that is not GPU work.
    ami_alias         = "al2023@latest"
    capacity_types    = ["on-demand", "spot"]
    instance_category = ["c", "m", "r"]
    instance_gen_min  = 5
    cpu_limit         = 64
    expire_after      = "168h"
    consolidate_after = "1m"
  }

  config    = merge(local.defaults, module.context.spec)
  karpenter = module.cluster.karpenter

  # Release names/namespace/service account must match core-platform's Pod
  # Identity binding (clusters.<key>.karpenter).
  namespace       = try(local.karpenter.namespace, "karpenter")
  service_account = try(local.karpenter.service_account, "karpenter")

  node_class = {
    role             = try(local.karpenter.node_role_name, "karpenter-missing")
    subnetIds        = module.cluster.node_subnet_ids
    securityGroupIds = compact([module.cluster.node_security_group_id])
    amiAlias         = local.config.ami_alias
    tags             = merge(module.context.tags, { Cluster = local.cluster_key })
  }
}
