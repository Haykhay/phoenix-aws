locals {
  defaults = {
    enabled  = true
    clusters = tomap({})
  }

  config = merge(local.defaults, module.context.spec)

  # `base_name_prefix` (`<env_id>-<region code>`) comes from modules/context. The override exists only to pin an existing name
  # through a migration.
  #
  # No `-cache` segment: an ElastiCache replication group ID caps at 40
  # characters and every name here already carries the cluster key, so the
  # segment cost six characters and said nothing the ID did not.
  name_prefix              = coalesce(try(local.config.name_prefix, null), local.base_name_prefix)
  core_platform_state_key  = "${local.environment}/${local.scope}/core-platform/terraform.tfstate"
  read_core_platform_state = try(local.config.allow_eks_node_security_group, true)

  # Each cluster sits in the VPC it names, else the one this resource set binds
  # to (local.core_network, from modules/context), which is itself the
  # network's default unless the resource set names one.
  cluster_networks = {
    for name, cluster in local.elasticache_clusters : name => (
      try(cluster.vpc, null) == null
      ? local.core_network
      : try(local.core_networks[cluster.vpc], null)
    )
  }

  # Caches live in the data subnets; VPCs that do not separate the data and
  # platform roles fall back to all private subnets.
  # Without a network the placeholder keeps the upstream module from failing on
  # an empty subnet list, so the plan stops on terraform_data.validation's
  # message instead; that precondition fails the plan, so it never reaches AWS.
  cluster_subnet_ids = {
    for name, network in local.cluster_networks : name => try(
      length(network.data_subnet_ids) > 0 ? network.data_subnet_ids : network.private_subnet_ids,
      ["core-network-missing"],
    )
  }

  eks_node_security_group_ids = local.read_core_platform_state ? compact([
    try(data.terraform_remote_state.core_platform[0].outputs.node_security_group_id, null)
  ]) : []

  allowed_cidr_blocks = distinct(try(local.config.allowed_cidr_blocks, []))

  # Per cluster: explicitly allowed groups plus the node groups of whichever
  # EKS clusters it is bound to.
  allowed_security_group_ids = {
    for name, cluster in local.elasticache_clusters : name => compact(distinct(concat(
      try(cluster.allowed_security_group_ids, local.config.allowed_security_group_ids, []),
      try(local.item_node_security_group_ids[name], []),
    )))
  }

  elasticache_clusters = local.config.enabled ? {
    for name, cluster in try(local.config.clusters, {}) : name => merge(cluster, {
      base_name_postfix = coalesce(try(cluster.base_name_postfix, null), name)
    })
  } : {}

  # Ownership. Per item where a module creates several.
  elasticache_clusters_ownership_tags = {
    for name, item in local.elasticache_clusters : name => {
      for key, value in merge(
        try(module.context.config.tags, {}),
        try(local.config.tags, {}),
        try(item.tags, {}),
        { CreatedBy = coalesce(
          try(item.tags.CreatedBy, null),
          try(local.config.tags.CreatedBy, null),
          try(module.context.config.tags.CreatedBy, null),
          terraform_data.elasticache_clusters_created_by[name].output,
        ) },
      ) : key => tostring(value)
    }
  }

  # Which clusters may reach these resources. A cluster grants its node security
  # group ingress, so this is a security boundary: with several configured it has
  # to be named rather than guessed. Unambiguous with exactly one.
  platform_clusters = try(data.terraform_remote_state.core_platform[0].outputs.clusters, {})

  default_cluster_binding = length(local.platform_clusters) == 1 ? keys(local.platform_clusters) : []

  # item -> the cluster keys whose nodes it trusts
  item_cluster_bindings = {
    for name, item in local.elasticache_clusters : name => (
      try(item.eks_clusters, null) != null ? item.eks_clusters :
      try(local.config.eks_clusters, null) != null ? local.config.eks_clusters :
      local.default_cluster_binding
    ) if try(item.allow_eks_node_security_group, try(local.config.allow_eks_node_security_group, true))
  }

  item_node_security_group_ids = {
    for name, keys_ in local.item_cluster_bindings : name => compact([
      for k in keys_ : try(local.platform_clusters[k].node_security_group_id, null)
    ])
  }

}
