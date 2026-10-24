locals {
  defaults = {
    enabled       = true
    chart_version = "v26.7.1"
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "gpu-operator"
}
