locals {
  defaults = {
    enabled       = true
    chart_version = "0.29.0"
    app_version   = "1.30.0"
    pg_image_tag  = "18.4-system-trixie"
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace       = try(local.config.settings.namespace, "cnpg-system")
  release_name    = try(local.config.settings.release_name, "cloudnative-pg")
  chart           = try(local.config.settings.chart, "cloudnative-pg")
  repository      = try(local.config.settings.repository, "https://cloudnative-pg.github.io/charts")
  chart_version   = try(local.config.settings.chart_version, local.config.chart_version)
  chart_values    = merge(local.default_values, coalesce(try(local.config.settings.values, null), {}))
  wait            = try(local.config.settings.wait, true)
  wait_for_jobs   = try(local.config.settings.wait_for_jobs, true)
  timeout         = try(local.config.settings.timeout, 600)
  atomic          = try(local.config.settings.atomic, true)
  cleanup_on_fail = try(local.config.settings.cleanup_on_fail, true)

  # Upstream images by default. image_registry (e.g. the group's ECR
  # pull-through prefix, <account>.dkr.ecr.<region>.amazonaws.com/artifactory)
  # makes the operator pull both its own and the Postgres image from there.
  image_registry = try(local.config.image_registry, null)

  default_values = local.image_registry == null ? {} : {
    config = {
      data = {
        OPERATOR_IMAGE_NAME = "${local.image_registry}/ghcr.io/cloudnative-pg/cloudnative-pg:${local.config.app_version}"
        POSTGRES_IMAGE_NAME = "${local.image_registry}/ghcr.io/cloudnative-pg/postgresql:${local.config.pg_image_tag}"
      }
    }
  }
}
