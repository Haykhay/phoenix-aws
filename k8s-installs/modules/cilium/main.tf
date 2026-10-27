data "aws_vpc" "cluster" {
  id = module.cluster.vpc_id
}

resource "helm_release" "this" {
  count           = local.config.enabled ? 1 : 0
  name            = local.release_name
  chart           = local.chart
  repository      = local.repository
  version         = local.chart_version
  namespace       = local.namespace
  wait            = local.wait
  timeout         = local.timeout
  atomic          = local.atomic
  cleanup_on_fail = local.cleanup_on_fail

  values = [
    yamlencode(local.chart_values)
  ]

  lifecycle {
    precondition {
      condition     = module.context.platform_network != null
      error_message = "cilium needs spec.network (the platform settings) for the default egress policy's shared segment."
    }
  }
}

# The default CiliumClusterwideNetworkPolicy, as a local chart so it installs
# after the CRDs exist (a kubernetes_manifest would need them at plan).
resource "helm_release" "policy" {
  count     = local.config.enabled ? 1 : 0
  name      = "${local.release_name}-default-policy"
  chart     = "${path.module}/manifests/cilium-policy"
  namespace = local.namespace
  wait      = local.wait
  timeout   = local.timeout
  atomic    = local.atomic

  values = [
    yamlencode(local.policy_values)
  ]

  depends_on = [helm_release.this]
}
