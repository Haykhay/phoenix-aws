locals {
  defaults = {
    enabled       = true
    chart_version = "0.0.8"
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "clickhouse-operator"
}
