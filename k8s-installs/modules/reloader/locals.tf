locals {
  defaults = {
    enabled       = true
    chart_version = "2.2.12"
    app_version   = "v1.4.17"
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace       = try(local.config.settings.namespace, "reloader")
  release_name    = try(local.config.settings.release_name, "reloader")
  chart           = try(local.config.settings.chart, "reloader")
  repository      = try(local.config.settings.repository, "https://stakater.github.io/stakater-charts")
  chart_version   = try(local.config.settings.chart_version, local.config.chart_version)
  chart_values    = merge(local.default_values, coalesce(try(local.config.settings.values, null), {}))
  wait            = try(local.config.settings.wait, true)
  wait_for_jobs   = try(local.config.settings.wait_for_jobs, true)
  timeout         = try(local.config.settings.timeout, 600)
  atomic          = try(local.config.settings.atomic, true)
  cleanup_on_fail = try(local.config.settings.cleanup_on_fail, true)

  default_values = {
    reloader = {
      autoReloadAll = try(local.config.settings.auto_reload_all, false)
    }
  }
}
