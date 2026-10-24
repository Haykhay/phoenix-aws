# Guardrails that must hold before anything is created.
resource "terraform_data" "validation" {
  count = length(local.elasticache_clusters) > 0 ? 1 : 0

  input = keys(local.elasticache_clusters)

  lifecycle {
    precondition {
      condition     = alltrue([for name, network in local.cluster_networks : network != null])
      error_message = "No network for ${join(", ", [for name, network in local.cluster_networks : name if network == null])}: core-network has no state for this environment/scope (apply it first), or a `vpc` names a VPC core-network does not have."
    }
    # Granting a cluster's node security group ingress is a security boundary:
    # with several EKS clusters, guessing which one may reach a data store
    # would silently grant or deny the wrong one.
    precondition {
      condition     = length(local.platform_clusters) <= 1 || length(local.unbound_items) == 0
      error_message = "${join(", ", local.unbound_items)} must name eks_clusters: this environment has ${length(local.platform_clusters)} EKS clusters (${join(", ", keys(local.platform_clusters))}). Set eks_clusters, or allow_eks_node_security_group: false."
    }
    # An ElastiCache replication group ID caps at 40 characters. Fail rather
    # than truncate or hash: a silently shortened name could collide.
    precondition {
      condition     = alltrue([for name, item in local.elasticache_clusters : length("${local.name_prefix}-${item.base_name_postfix}") <= 40])
      error_message = "ElastiCache replication group IDs are limited to 40 characters: ${join(", ", [for name, item in local.elasticache_clusters : "${local.name_prefix}-${item.base_name_postfix} (${length("${local.name_prefix}-${item.base_name_postfix}")})" if length("${local.name_prefix}-${item.base_name_postfix}") > 40])}. Shorten the cluster key or set base_name_postfix / name_prefix in the spec."
    }
  }
}

locals {
  # Items that trust EKS node security groups without naming which clusters.
  unbound_items = [
    for name, item in local.elasticache_clusters : name
    if try(item.allow_eks_node_security_group, try(local.config.allow_eks_node_security_group, true)) && try(item.eks_clusters, null) == null && try(local.config.eks_clusters, null) == null
  ]
}
