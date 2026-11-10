locals {
  defaults = {
    enabled       = true
    chart_version = "1.18.0" # driver v1.10.0, released 2026-10-01
  }

  config = merge(local.defaults, module.context.spec)

  # Where vLLM runs; the claim must live beside it.
  namespace = "models"
  pvc_name  = "model-cache"

  cache     = try(data.terraform_remote_state.model_cache.outputs, {})
  has_cache = can(local.cache.file_system_id)

  # phoenix-shared: one FSx for Lustre file system per claim (dynamic).
  service_account = "fsx-csi-controller-sa" # the chart's controller account
  role_name       = "${local.name_prefix}-fsx-csi"
  tag_key         = "PhoenixCluster"
}
