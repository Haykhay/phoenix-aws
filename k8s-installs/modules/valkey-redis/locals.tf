locals {
  defaults = {
    enabled       = true
    chart_version = "0.4.1"
    app_version   = "v0.4.0"
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace       = try(local.config.settings.namespace, "valkey-operator")
  release_name    = try(local.config.settings.release_name, "valkey-operator")
  chart           = try(local.config.settings.chart, "valkey-operator")
  repository      = try(local.config.settings.repository, "https://valkey-io.github.io/valkey-helm/")
  chart_version   = try(local.config.settings.chart_version, local.config.chart_version)
  chart_values    = coalesce(try(local.config.settings.values, null), {})
  wait            = try(local.config.settings.wait, true)
  wait_for_jobs   = try(local.config.settings.wait_for_jobs, true)
  timeout         = try(local.config.settings.timeout, 600)
  atomic          = try(local.config.settings.atomic, true)
  cleanup_on_fail = try(local.config.settings.cleanup_on_fail, true)
}
