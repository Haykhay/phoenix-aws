resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = local.release_name
  chart            = local.chart
  repository       = local.repository
  version          = local.chart_version
  namespace        = local.namespace
  create_namespace = true
  wait             = local.wait
  wait_for_jobs    = local.wait_for_jobs
  timeout          = local.timeout
  atomic           = local.atomic
  cleanup_on_fail  = local.cleanup_on_fail

  values = [
    yamlencode(local.chart_values)
  ]
}
