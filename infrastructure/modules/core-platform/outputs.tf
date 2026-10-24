# `clusters` is the contract. The flat outputs below are deprecated shims that
# resolve against the default cluster, kept so consumers that predate multiple
# clusters keep working — k8s-installs reads cluster_name, and the data-* sets
# read node_security_group_id. New consumers should index `clusters` by name.
output "clusters" {
  description = "Every cluster in this resource set, keyed by its config name."
  value = {
    for name, cluster in local.clusters : name => {
      cluster_name     = module.eks[name].cluster_name
      cluster_id       = module.eks[name].cluster_id
      cluster_arn      = module.eks[name].cluster_arn
      cluster_endpoint = module.eks[name].cluster_endpoint
      # Lets k8s-installs configure helm/kubernetes without an EKS API call.
      cluster_certificate_authority_data = module.eks[name].cluster_certificate_authority_data
      cluster_kms_key_arn                = module.eks[name].kms_key_arn
      cluster_security_group_id          = module.eks[name].cluster_security_group_id
      node_security_group_id             = module.eks[name].node_security_group_id
      version                            = cluster.version
      vpc                                = cluster.vpc
      vpc_id                             = try(local.cluster_networks[name].vpc_id, null)
      # Where nodes run; Karpenter's node classes select these by ID.
      node_subnet_ids = local.cluster_subnet_ids[name]
      # null unless the cluster sets karpenter.enabled. Consumed by
      # k8s-installs' karpenter module (see karpenter.tf).
      karpenter = contains(keys(local.karpenter_clusters), name) ? {
        controller_role_arn = module.karpenter[name].iam_role_arn
        node_role_name      = module.karpenter[name].node_iam_role_name
        node_role_arn       = module.karpenter[name].node_iam_role_arn
        queue_name          = module.karpenter[name].queue_name
        namespace           = module.karpenter[name].namespace
        service_account     = module.karpenter[name].service_account
      } : null
    }
  }
}

output "default_cluster_name" {
  description = "Config key of the cluster consumers bind to when they name none."
  value       = local.config.enabled ? local.default_cluster_name : null
}

output "cluster_names" {
  description = "Config keys of every cluster in this resource set."
  value       = keys(local.clusters)
}

# --- Deprecated single-cluster shims, resolving against the default cluster ---

output "cluster_name" {
  value = local.config.enabled ? module.eks[local.default_cluster_name].cluster_name : null
}

output "cluster_id" {
  value = local.config.enabled ? module.eks[local.default_cluster_name].cluster_id : null
}

output "cluster_arn" {
  value = local.config.enabled ? module.eks[local.default_cluster_name].cluster_arn : null
}

output "cluster_endpoint" {
  value = local.config.enabled ? module.eks[local.default_cluster_name].cluster_endpoint : null
}

output "cluster_certificate_authority_data" {
  value     = local.config.enabled ? module.eks[local.default_cluster_name].cluster_certificate_authority_data : null
  sensitive = true
}

output "cluster_kms_key_arn" {
  value = local.config.enabled ? module.eks[local.default_cluster_name].kms_key_arn : null
}

output "node_security_group_id" {
  value = local.config.enabled ? module.eks[local.default_cluster_name].node_security_group_id : null
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    resource_set = "core-platform"
    clusters     = keys(local.clusters)
    default      = local.config.enabled ? local.default_cluster_name : null
  }
}
