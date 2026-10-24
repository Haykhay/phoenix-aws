locals {
  defaults = {
    enabled   = true
    instances = tomap({})
  }

  config = merge(local.defaults, module.context.spec)

  # `base_name_prefix` (`<env_id>-<region code>`) comes from modules/context. The override exists only to pin an existing name
  # through a migration.
  name_prefix              = coalesce(try(local.config.name_prefix, null), local.base_name_prefix)
  db_prefix                = try(local.config.db_prefix, "rds")
  rds_base_name            = "${local.name_prefix}-${local.db_prefix}"
  secret_name_prefix       = "/db/${local.db_prefix}/${local.name_prefix}"
  core_platform_state_key  = "${local.environment}/${local.scope}/core-platform/terraform.tfstate"
  read_core_platform_state = try(local.config.allow_eks_node_security_group, true)

  # Each instance sits in the VPC it names, else the one this resource set binds
  # to (local.core_network, from modules/context), which is itself the
  # network's default unless the resource set names one.
  instance_networks = {
    for name, instance in local.instances : name => (
      try(instance.vpc, null) == null
      ? local.core_network
      : try(local.core_networks[instance.vpc], null)
    )
  }

  # Databases live in the data subnets; VPCs that do not separate the data and
  # platform roles fall back to all private subnets.
  # Without a network the placeholder keeps the upstream module from failing on
  # an empty subnet list, so the plan stops on terraform_data.validation's
  # message instead; that precondition fails the plan, so it never reaches AWS.
  instance_subnet_ids = {
    for name, network in local.instance_networks : name => try(
      length(network.data_subnet_ids) > 0 ? network.data_subnet_ids : network.private_subnet_ids,
      ["core-network-missing"],
    )
  }

  # Per instance: explicitly allowed groups plus the node groups of whichever
  # clusters it is bound to.
  allowed_security_group_ids = {
    for name, instance in local.instances : name => compact(distinct(concat(
      try(instance.allowed_security_group_ids, local.config.allowed_security_group_ids, []),
      try(local.item_node_security_group_ids[name], []),
    )))
  }
  allowed_cidr_blocks = distinct(try(local.config.allowed_cidr_blocks, []))

  default_port_by_engine = {
    mysql    = 3306
    postgres = 5432
  }

  default_logs_by_engine = {
    mysql    = ["error", "general", "slowquery"]
    postgres = ["postgresql", "upgrade"]
  }

  instances = local.config.enabled ? {
    for name, instance in try(local.config.instances, {}) : name => merge(instance, {
      engine                              = lower(instance.engine)
      port                                = coalesce(try(instance.port, null), lookup(local.default_port_by_engine, lower(instance.engine), 5432))
      base_name_postfix                   = coalesce(try(instance.base_name_postfix, null), name)
      username                            = coalesce(try(instance.username, null), replace(name, "-", "_"))
      db_name                             = coalesce(try(instance.db_name, null), replace(name, "-", "_"))
      replica_enabled                     = try(instance.replica_enabled, false)
      parameters                          = coalesce(try(instance.parameters, null), [])
      enabled_cloudwatch_logs_exports     = length(coalesce(try(instance.enabled_cloudwatch_logs_exports, null), [])) > 0 ? instance.enabled_cloudwatch_logs_exports : lookup(local.default_logs_by_engine, lower(instance.engine), [])
      cloudwatch_log_group_retention_days = coalesce(try(instance.cloudwatch_log_group_retention_days, null), try(local.config.cloudwatch_log_retention_days, 7))

      # Defaults so a request form only needs engine, version, family, class
      # and storage. backup_window null lets AWS pick one.
      auto_minor_version_upgrade = try(instance.auto_minor_version_upgrade, true)
      backup_window              = try(instance.backup_window, null)
      backup_retention_period    = try(instance.backup_retention_period, 7)
      apply_immediately          = try(instance.apply_immediately, false)
    })
  } : {}

  # Ownership. Per item where a module creates several.
  instances_ownership_tags = {
    for name, item in local.instances : name => {
      for key, value in merge(
        try(module.context.config.tags, {}),
        try(local.config.tags, {}),
        try(item.tags, {}),
        { CreatedBy = coalesce(
          try(item.tags.CreatedBy, null),
          try(local.config.tags.CreatedBy, null),
          try(module.context.config.tags.CreatedBy, null),
          terraform_data.instances_created_by[name].output,
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
    for name, item in local.instances : name => (
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
