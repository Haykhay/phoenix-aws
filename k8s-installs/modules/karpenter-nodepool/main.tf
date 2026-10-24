# One GPU NodePool + EC2NodeClass per GPU type (file karpenter-nodepool.<type>.yaml).
# Nodes carry taint nvidia.com/gpu=true:NoSchedule and label phoenix/gpu=<type>;
# only workloads that ask for that GPU land there. Needs the karpenter unit
# (controller + CRDs) applied first.
resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "karpenter-nodepool is per GPU type: name the file karpenter-nodepool.<gpu type>.yaml."
    }
    precondition {
      condition     = !local.config.enabled || length(local.config.instance_families) > 0
      error_message = "spec.instance_families is required (from the phoenix-gpu entity, e.g. [g6] for l4)."
    }
    precondition {
      condition     = !local.config.enabled || local.karpenter != null
      error_message = "core-platform has no Karpenter for cluster \"${local.cluster_key}\"."
    }
  }
}

resource "helm_release" "this" {
  count     = local.config.enabled ? 1 : 0
  name      = "karpenter-nodepool-${local.gpu_type}"
  chart     = "${path.module}/manifests/gpu-nodepool"
  namespace = try(local.karpenter.namespace, "karpenter")

  values = [yamlencode({
    name             = local.pool_name
    gpuType          = local.gpu_type
    instanceFamilies = local.config.instance_families
    gpuCountMax      = local.config.gpu_count_max
    gpuLimit         = local.config.gpu_limit
    capacityTypes    = local.config.capacity_types
    expireAfter      = local.config.expire_after
    consolidateAfter = local.config.consolidate_after
    nodeClass = {
      role             = try(local.karpenter.node_role_name, "karpenter-missing")
      subnetIds        = module.cluster.node_subnet_ids
      securityGroupIds = compact([module.cluster.node_security_group_id])
      amiAlias         = local.config.ami_alias
      volumeSize       = local.config.volume_size
      tags             = merge(module.context.tags, { Cluster = local.cluster_key, GpuType = local.gpu_type })
    }
  })]

  depends_on = [terraform_data.validation]
}
