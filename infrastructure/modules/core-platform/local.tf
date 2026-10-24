locals {
  # Resource-set level shape, from the YAML `spec`. `clusters` is a map of named EKS clusters;
  # `cluster_defaults` holds settings shared by all of them so they are written once.
  resource_set_defaults = {
    # The YAML file existing enables the unit; `enabled: false` is a kill switch.
    enabled          = true
    cluster_defaults = tomap({})
    clusters         = tomap({})

    # CIDRs allowed to reach the private API endpoint. Unset means no rule:
    # network design (VPN, self-hosted runners) is decided outside this module.
    vpn_cidr        = null
    ci_runners_cidr = null

    # Pod Identity bindings to the group's observability roles (observability.tf).
    observability = {}
  }

  config = merge(local.resource_set_defaults, module.context.spec)

  # Per-cluster defaults. Anything here can be overridden in `cluster_defaults`
  cluster_defaults = {
    cluster_name                             = null
    vpc                                      = null
    version                                  = null
    endpoint_public_access                   = false
    enable_irsa                              = false
    enable_cluster_creator_admin_permissions = false
    cluster_enabled_log_types                = tolist(["api", "audit", "authenticator", "controllerManager", "scheduler"])
    cluster_addons                           = tomap({})
    node_role_additional_policies            = tomap({})
    admin_role_names                         = tolist([])
    access_entries                           = { admin = tomap({}), view = tomap({}) }
    pod_identity                             = tomap({})
    karpenter                                = tomap({})
    node_groups                              = tomap({})
    tags                                     = tomap({})
  }

  effective_cluster_defaults = merge(local.cluster_defaults, lookup(local.config, "cluster_defaults", {}))

  # Nested maps are merged per key, not replaced. `merge` is shallow, so a
  # cluster that overrides one addon would otherwise drop the defaults' other
  # entries — and a dropped addon is a destroyed addon. Losing vpc-cni that way
  # takes pod networking with it.
  nested_map_keys = ["cluster_addons", "node_groups", "pod_identity", "karpenter", "node_role_additional_policies"]

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
      # access_entries nests one level deeper: the principals live under
      # `admin` and `view`, so merging the outer key alone would still drop
      # shared principals.
      {
        access_entries = {
          for level in ["admin", "view"] : level => merge(
            try(local.effective_cluster_defaults.access_entries[level], {}),
            try(cluster.access_entries[level], {}),
          )
        }
      },
    )
  }

  # `base_name_prefix` (`<env_id>-<region code>`) comes from modules/context,
  # where the naming scheme lives.
  name_prefix = local.base_name_prefix

  clusters = {
    for name, cluster in local.merged_clusters : name => merge(cluster, {
      cluster_name = coalesce(cluster.cluster_name, "${local.name_prefix}-${name}-eks")
    }) if local.config.enabled
  }

  # Each cluster runs in the platform subnets of the VPC it binds to. A cluster
  # that names no VPC uses the network's default. null when core-network has
  # no state yet (or any more): terraform_data.validation stops a create/update
  # with a clear message, and a destroy still plans.
  cluster_networks = {
    for name, cluster in local.clusters : name => (
      cluster.vpc == null ? local.core_network : try(local.core_networks[cluster.vpc], null)
    )
  }

  # Without a network the placeholder keeps the upstream module from failing
  # on an empty subnet list, so the plan stops on terraform_data.validation's
  # message instead. It can never reach AWS: that precondition fails the plan.
  # Dropping the cluster from module.eks instead would plan its destruction.
  cluster_subnet_ids = {
    for name, network in local.cluster_networks : name => try(
      length(network.platform_subnet_ids) > 0 ? network.platform_subnet_ids : network.private_subnet_ids,
      ["core-network-missing"],
    )
  }

  endpoint_ingress_rules = merge(
    local.config.vpn_cidr == null ? {} : {
      vpn = {
        description = "VPN to EKS Endpoint"
        protocol    = "tcp"
        from_port   = 443
        to_port     = 443
        type        = "ingress"
        cidr_blocks = [local.config.vpn_cidr]
      }
    },
    local.config.ci_runners_cidr == null ? {} : {
      ci_runners = {
        description = "Self-hosted CI runners to EKS Endpoint"
        protocol    = "tcp"
        from_port   = 443
        to_port     = 443
        type        = "ingress"
        cidr_blocks = [local.config.ci_runners_cidr]
      }
    },
  )
  default_admin_role_names = toset([
    "DevOps",
    "DevOpsLead",
    "SolutionArchitect",
  ])

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
          terraform_data.cluster_created_by[name].output,
        ) },
      ) : key => tostring(value)
    }
  }

  # Name is the cluster's own name, so clusters in one resource set can be told
  # apart. It does not roll nodes: terraform-aws-eks puts the node group's own
  # Name after these tags in the launch template's tag_specifications, and the
  # launch template's resource-level tags do not create a new version.
  tags = {
    for name, cluster in local.clusters : name => merge(local.ownership_tags[name], {
      Name        = cluster.cluster_name
      Environment = local.environment
      Region      = local.region
    })
  }

  node_role_policies = {
    for name, cluster in local.clusters : name => merge(
      {
        AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        AmazonSSMPatchAssociation          = "arn:aws:iam::aws:policy/AmazonSSMPatchAssociation"
        CloudWatchAgentServerPolicy        = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        AmazonEC2ContainerRegistryPullOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
      },
      cluster.node_role_additional_policies,
    )
  }

  admin_role_names = {
    for name, cluster in local.clusters :
    name => sort(tolist(setunion(local.default_admin_role_names, toset(cluster.admin_role_names))))
  }

  access_entries = {
    for name, cluster in local.clusters : name => merge(
      {
        for role_name in local.admin_role_names[name] :
        role_name => {
          principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${role_name}"
          policy_associations = {
            admin = {
              policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
              access_scope = {
                type = "cluster"
              }
            }
          }
        }
      },
      {
        for admin, principal_arn in try(cluster.access_entries.admin, {}) :
        admin => {
          principal_arn = principal_arn
          policy_associations = {
            admin = {
              policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
              access_scope = {
                type = "cluster"
              }
            }
          }
        }
      },
      # Read-only: kubectl get/list/watch, no secrets (AmazonEKSViewPolicy).
      {
        for viewer, principal_arn in try(cluster.access_entries.view, {}) :
        viewer => {
          principal_arn = principal_arn
          policy_associations = {
            view = {
              policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
              access_scope = {
                type = "cluster"
              }
            }
          }
        }
      },
    )
  }

  # EKS allows one access entry per principal per cluster, and the map above is
  # keyed by name, so a name or principal in both admin and view would either
  # silently drop one or fail at apply. Checked in main.tf's validation.
  access_entry_conflicts = {
    for name, cluster in local.clusters : name => setintersection(
      toset(concat(
        [for role_name in local.admin_role_names[name] : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${role_name}"],
        values(try(cluster.access_entries.admin, {})),
        keys(try(cluster.access_entries.admin, {})),
        local.admin_role_names[name],
      )),
      toset(concat(
        values(try(cluster.access_entries.view, {})),
        keys(try(cluster.access_entries.view, {})),
      )),
    )
  }

  # Phase 1: only the Pod Identity agent goes into module.eks so it is running
  # before any association-dependent addon (e.g. EBS CSI) is installed.
  # If eks-pod-identity-agent appears in cluster_addons config, pass the resolved
  # version through; otherwise pass {} and let module.eks manage the version.
  effective_cluster_addons = {
    for name, cluster in local.clusters : name => {
      "eks-pod-identity-agent" = can(cluster.cluster_addons["eks-pod-identity-agent"]) ? {
        addon_version = try(local.resolved_addon_version["${name}/eks-pod-identity-agent"], null)
      } : {}
    }
  }

  # All user-configured addons (both phases), keyed "cluster/addon".
  # Used as the single source for version resolution so eks-pod-identity-agent
  # can be version-pinned or most_recent'd from the YAML like any other addon.
  all_configured_addons = merge([
    for cluster_key, cluster in local.clusters : {
      for addon, spec in cluster.cluster_addons :
      "${cluster_key}/${addon}" => merge(spec, {
        cluster_key = cluster_key
        addon_name  = addon
      })
    }
  ]...)

  # Phase 3: user-configured addons, keyed "cluster/addon", created after
  # Pod Identity associations exist.
  # eks-pod-identity-agent is excluded here — it lives in Phase 1 (module.eks)
  # and managing it in Phase 3 as well would create a duplicate resource conflict.
  post_pi_addons = {
    for k, v in local.all_configured_addons : k => v
    if v.addon_name != "eks-pod-identity-agent"
  }

  # Clusters that asked for the EBS CSI pod identity role.
  ebs_csi_clusters = {
    for name, cluster in local.clusters :
    name => cluster if try(cluster.pod_identity.aws_ebs_csi.enabled, false)
  }

  default_cluster_name = coalesce(
    try(local.config.default_cluster, null),
    length(local.clusters) == 1 ? keys(local.clusters)[0] : null,
    "__unset__",
  )

  # An addon_version is built for one Kubernetes version. The same pin on
  # clusters running different versions plans green and fails part-way
  # through apply, so it is refused at plan (terraform_data.validation).
  addon_pin_versions = {
    for pin in flatten([
      for cluster_key, cluster in local.clusters : [
        for addon, spec in cluster.cluster_addons : {
          key     = "${addon}@${spec.addon_version}"
          version = cluster.version
        } if try(spec.addon_version, null) != null
      ]
    ]) : pin.key => pin.version...
  }
  addon_pin_conflicts = [for pin, versions in local.addon_pin_versions : pin if length(distinct(versions)) > 1]

  # Priority per addon: (1) explicit addon_version, (2) most_recent data source,
  # (3) null — let AWS pick the default at creation time (version unmanaged).
  # Covers all_configured_addons so eks-pod-identity-agent is resolved the same
  # way as Phase 3 addons when it appears in cluster_addons config.
  resolved_addon_version = {
    for k, v in local.all_configured_addons : k =>
    try(v.addon_version, null) != null ? v.addon_version :
    try(data.aws_eks_addon_version.latest[k].version, null)
  }
}
