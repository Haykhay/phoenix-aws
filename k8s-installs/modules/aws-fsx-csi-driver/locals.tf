locals {
  defaults = {
    enabled       = true
    chart_version = "1.18.0" # driver v1.10.0, released 2026-10-01
  }

  config = merge(local.defaults, module.context.spec)

  # Where vLLM runs; the claim must live beside it.
  namespace = "models"
  pvc_name  = "model-cache"

  cache = try(data.terraform_remote_state.model_cache.outputs, {})
}
