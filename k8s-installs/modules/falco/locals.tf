locals {
  defaults = {
    enabled       = true
    chart_version = "0.3.1"
    app_version   = "0.4.1"
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace       = try(local.config.settings.namespace, "falco-operator")
  release_name    = try(local.config.settings.release_name, "falco-operator")
  chart           = try(local.config.settings.chart, "falco-operator")
  repository      = try(local.config.settings.repository, "https://falcosecurity.github.io/charts")
  chart_version   = try(local.config.settings.chart_version, local.config.chart_version)
  chart_values    = coalesce(try(local.config.settings.values, null), {})
  wait            = try(local.config.settings.wait, true)
  wait_for_jobs   = try(local.config.settings.wait_for_jobs, false)
  timeout         = try(local.config.settings.timeout, 300)
  atomic          = try(local.config.settings.atomic, true)
  cleanup_on_fail = try(local.config.settings.cleanup_on_fail, true)

  # OCI artifact tags — pin these per environment to avoid uncontrolled updates.
  rules_tag   = try(local.config.settings.rules_tag, "latest")
  plugin_tag  = try(local.config.settings.plugin_tag, "latest")
  k8smeta_tag = try(local.config.settings.k8smeta_tag, "latest")
}
