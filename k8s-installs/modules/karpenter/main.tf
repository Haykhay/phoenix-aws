resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.karpenter != null
      error_message = "core-platform has no Karpenter for cluster \"${local.cluster_key}\": set clusters.${local.cluster_key}.karpenter.enabled in its YAML and apply it first."
    }
  }
}

resource "helm_release" "controller" {
  count            = local.config.enabled ? 1 : 0
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    serviceAccount = { name = local.service_account }
    settings = {
      clusterName       = local.cluster_name
      clusterEndpoint   = module.cluster.cluster_endpoint
      interruptionQueue = try(local.karpenter.queue_name, "")
    }
  })]

  depends_on = [terraform_data.validation]
}

# Default EC2NodeClass + NodePool. A local chart rather than kubernetes_manifest:
# the CRDs arrive with the controller chart, and kubernetes_manifest needs them
# at plan time.
resource "helm_release" "defaults" {
  count     = local.config.enabled ? 1 : 0
  name      = "karpenter-defaults"
  chart     = "${path.module}/manifests/karpenter-defaults"
  namespace = local.namespace

  values = [yamlencode({
    nodeClass = merge(local.node_class, { name = "default" })
    nodePool = {
      name             = "default"
      capacityTypes    = local.config.capacity_types
      instanceCategory = local.config.instance_category
      instanceGenMin   = tostring(local.config.instance_gen_min)
      cpuLimit         = local.config.cpu_limit
      expireAfter      = local.config.expire_after
      consolidateAfter = local.config.consolidate_after
    }
  })]

  depends_on = [helm_release.controller]
}
