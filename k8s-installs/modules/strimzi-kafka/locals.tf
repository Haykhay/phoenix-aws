locals {
  defaults = {
    enabled       = true
    chart_version = "1.1.0"
    app_version   = "1.1.0"
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace       = try(local.config.settings.namespace, "strimzi-operator")
  release_name    = try(local.config.settings.release_name, "strimzi-kafka-operator")
  chart           = try(local.config.settings.chart, "strimzi-kafka-operator")
  repository      = try(local.config.settings.repository, "https://strimzi.io/charts/")
  chart_version   = try(local.config.settings.chart_version, local.config.chart_version)
  chart_values    = coalesce(try(local.config.settings.values, null), {})
  wait            = try(local.config.settings.wait, true)
  wait_for_jobs   = try(local.config.settings.wait_for_jobs, true)
  timeout         = try(local.config.settings.timeout, 600)
  atomic          = try(local.config.settings.atomic, true)
  cleanup_on_fail = try(local.config.settings.cleanup_on_fail, true)
}
