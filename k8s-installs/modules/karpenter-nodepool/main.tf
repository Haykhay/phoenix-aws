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
    precondition {
      condition     = !local.config.enabled || length(local.capacity_types) > 0
      error_message = "spec.capacity_types is empty and no capacity_reservations are named: the pool could never launch a node."
    }
    precondition {
      condition     = !local.config.enabled || !local.config.efa || length(setsubtract(local.config.instance_families, local.efa_families)) == 0
      error_message = "efa: true needs EFA-capable GPU families (${join(", ", local.efa_families)}); got ${join(", ", local.config.instance_families)}."
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
    capacityTypes    = local.capacity_types
    efa              = local.config.efa
    expireAfter      = local.config.expire_after
    consolidateAfter = local.config.consolidate_after
    nodeClass = {
      role                 = try(local.karpenter.node_role_name, "karpenter-missing")
      subnetIds            = module.cluster.node_subnet_ids
      securityGroupIds     = compact([module.cluster.node_security_group_id, try(aws_security_group.efa[0].id, "")])
      capacityReservations = local.config.capacity_reservations
      amiAlias             = local.config.ami_alias
      volumeSize           = local.config.volume_size
      tags                 = merge(module.context.tags, { Cluster = local.cluster_key, GpuType = local.gpu_type })
    }
  })]

  depends_on = [terraform_data.validation]
}

# EFA needs every node's interfaces to accept all traffic from the others.
resource "aws_security_group" "efa" {
  count       = local.config.enabled && local.config.efa ? 1 : 0
  name        = "${local.name_prefix}-efa"
  description = "EFA: all traffic between the ${local.pool_name} nodes"
  vpc_id      = module.cluster.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "efa_self" {
  count                        = length(aws_security_group.efa)
  security_group_id            = aws_security_group.efa[0].id
  referenced_security_group_id = aws_security_group.efa[0].id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "efa_self" {
  count                        = length(aws_security_group.efa)
  security_group_id            = aws_security_group.efa[0].id
  referenced_security_group_id = aws_security_group.efa[0].id
  ip_protocol                  = "-1"
}

# Advertises vpc.amazonaws.com/efa; Karpenter attaches EFA interfaces to nodes
# whose pods request it.
resource "helm_release" "efa_device_plugin" {
  count      = local.config.enabled && local.config.efa ? 1 : 0
  name       = "efa-device-plugin-${local.gpu_type}"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-efa-k8s-device-plugin"
  version    = local.efa_plugin
  namespace  = "kube-system"

  values = [yamlencode({
    nodeSelector = { "phoenix/gpu" = local.gpu_type }
    tolerations  = [{ key = "nvidia.com/gpu", operator = "Exists", effect = "NoSchedule" }]
  })]

  depends_on = [helm_release.this]
}
