locals {
  defaults = {
    enabled       = true
    chart_version = "2.5.33" # OpenCost 1.121.3, 2026-10-14
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "opencost"
}
