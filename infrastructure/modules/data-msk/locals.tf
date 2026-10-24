locals {
  resource_set_defaults = {
    enabled          = true
    cluster_defaults = tomap({})
    clusters         = tomap({})
  }

  config = merge(local.resource_set_defaults, module.context.spec)

  cluster_defaults = {
    name_prefix                   = null
    vpc                           = null
    kafka_version                 = "3.8.x.kraft"
    broker_instance_type          = "kafka.m7g.large"
    broker_per_zone               = 1
    allowed_cidr_blocks           = tolist([])
    allow_eks_node_security_group = true
    users                         = tolist([])
    # SASL/SCRAM usernames. Distinct from `users`, which are IAM roles for the
    # cluster policy — SCRAM authenticates with a username and password rather
    # than an IAM principal. Declaring any switches SCRAM auth on alongside IAM.
    scram_users = tolist([])
    tags        = tomap({})
  }

  effective_cluster_defaults = merge(local.cluster_defaults, lookup(local.config, "cluster_defaults", {}))

  # Nested collections merge per key rather than replacing, so a cluster naming
  # one entry keeps the defaults' others.
  nested_map_keys = ["tags"]

  merged_clusters = {
    for name, cluster in local.config.clusters : name => merge(
      local.effective_cluster_defaults,
      cluster,
      {
        for key in local.nested_map_keys : key => merge(
          try(local.effective_cluster_defaults[key], {}),
          try(cluster[key], {}),
        )
      },
    )
  }

  # `base_name_prefix` (`<env_id>-<region code>`) comes from modules/context. The per-cluster override exists only to pin an
  # existing name through a migration.
  clusters = {
    for name, cluster in local.merged_clusters : name => merge(cluster, {
      name_prefix = coalesce(cluster.name_prefix, "${local.base_name_prefix}-${name}")
    }) if local.config.enabled
  }

  core_platform_state_key = "${local.environment}/${local.scope}/core-platform/terraform.tfstate"

  read_core_platform_state = anytrue([
    for cluster in local.clusters : cluster.allow_eks_node_security_group
  ])

  # Which EKS clusters may reach these brokers. Granting a cluster's node
  # security group is a security boundary, so with several configured it has to
  # be named rather than guessed. Unambiguous with exactly one.
  platform_clusters = try(data.terraform_remote_state.core_platform[0].outputs.clusters, {})

  default_cluster_binding = length(local.platform_clusters) == 1 ? keys(local.platform_clusters) : []

  cluster_node_security_group_ids = {
    for name, cluster in local.clusters : name => compact([
      for k in(
        try(cluster.eks_clusters, null) != null ? cluster.eks_clusters : local.default_cluster_binding
      ) : try(local.platform_clusters[k].node_security_group_id, null)
    ]) if cluster.allow_eks_node_security_group
  }

  # Each cluster sits in the VPC it names, else the one this resource set binds
  # to (local.core_network, from modules/context).
  cluster_networks = {
    for name, cluster in local.clusters : name => (
      cluster.vpc == null
      ? local.core_network
      : try(local.core_networks[cluster.vpc], null)
    )
  }

  # Brokers sit in the platform subnets; VPCs that do not separate the data and
  # platform roles fall back to the first private subnets, one per broker AZ.
  # Without a network the placeholder keeps the upstream module from failing on
  # an empty subnet list, so the plan stops on terraform_data.validation's
  # message instead; that precondition fails the plan, so it never reaches AWS.
  cluster_subnet_ids = {
    for name, network in local.cluster_networks : name => try(
      length(network.platform_subnet_ids) > 0 ? network.platform_subnet_ids : slice(network.private_subnet_ids, 0, 3),
      ["core-network-missing"],
    )
  }


  # ------------------------------------------------
  # IAM cluster policy — users + ACLs
  # ------------------------------------------------

  # Kafka operation name → kafka-cluster: IAM actions
  _op_map = {
    topic = {
      "Read"            = ["kafka-cluster:ReadData", "kafka-cluster:DescribeTopic"]
      "Write"           = ["kafka-cluster:WriteData", "kafka-cluster:DescribeTopic"]
      "Create"          = ["kafka-cluster:CreateTopic"]
      "Delete"          = ["kafka-cluster:DeleteTopic"]
      "Describe"        = ["kafka-cluster:DescribeTopic"]
      "AlterConfigs"    = ["kafka-cluster:AlterTopic"]
      "DescribeConfigs" = ["kafka-cluster:DescribeTopicDynamicConfiguration"]
    }
    group = {
      "Read"     = ["kafka-cluster:ReadGroup", "kafka-cluster:DescribeGroup"]
      "Delete"   = ["kafka-cluster:DeleteGroup"]
      "Describe" = ["kafka-cluster:DescribeGroup"]
    }
  }

  _arn = "arn:aws:kafka:${local.region}:${data.aws_caller_identity.current.account_id}"

  # Clusters that declare users get a policy; the statements are per cluster
  # because the resource ARNs carry that cluster's name.
  policy_clusters = {
    for name, cluster in local.clusters : name => cluster if length(cluster.users) > 0
  }

  # SASL/SCRAM credentials, one per (cluster, username). Flattened to a single
  # map so the shared credentials module generates them all in one call.
  scram_credentials = merge([
    for cluster_name, cluster in local.clusters : {
      for username in cluster.scram_users :
      "${cluster_name}/${username}" => {
        cluster_key = cluster_name
        username    = username
      }
    }
  ]...)

  # Clusters with at least one SCRAM user; SCRAM auth is switched on for these
  # and left off everywhere else so no cluster gains an auth mode it never
  # asked for.
  scram_clusters = {
    for name, cluster in local.clusters : name => cluster if length(cluster.scram_users) > 0
  }

  cluster_policy_statements = {
    for name, cluster in local.policy_clusters : name => concat(
      # One Connect+DescribeCluster statement per user
      [for i, user in cluster.users : {
        Sid       = "Connect${i}"
        Effect    = "Allow"
        Principal = { AWS = [user.role_arn] }
        Action    = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
        Resource  = "${local._arn}:cluster/${cluster.name_prefix}/*"
      }],
      # One statement per user per ACL rule
      flatten([for i, user in cluster.users : [
        for j, acl in user.acls : {
          Sid       = "Acl${i}x${j}"
          Effect    = "Allow"
          Principal = { AWS = [user.role_arn] }
          Action = distinct(flatten([for op in acl.operations :
            lookup(lookup(local._op_map, acl.resource_type, {}), op, [])
          ]))
          Resource = "${local._arn}:${acl.resource_type}/${cluster.name_prefix}/*/${acl.name}"
        }
      ]])
    )
  }

  # The cluster the flat outputs resolve to. Unambiguous with one configured, so
  # only needed once there are several.
  default_cluster_name = coalesce(
    try(local.config.default_cluster, null),
    length(local.clusters) == 1 ? keys(local.clusters)[0] : null,
    "__unset__",
  )

  ownership_tags = {
    for name, cluster in local.clusters : name => {
      for key, value in merge(
        try(module.context.config.tags, {}),
        try(local.config.tags, {}),
        cluster.tags,
        { CreatedBy = coalesce(
          try(cluster.tags.CreatedBy, null),
          try(local.config.tags.CreatedBy, null),
          try(module.context.config.tags.CreatedBy, null),
          terraform_data.created_by[name].output,
        ) },
      ) : key => tostring(value)
    }
  }
}
