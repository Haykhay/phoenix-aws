locals {
  defaults = {
    enabled = true
    # The group's environment holding the observability unit (core-platform
    # binds the same one).
    observability_environment = "shared"
    chart_versions = {
      mimir   = "6.2.1"  # Mimir 3.2.1 — ingest storage with the chart's own Kafka
      loki    = "7.3.0"  # Loki 3.6.12
      tempo   = "3.1.0"  # Tempo 3.1.0, grafana-community repo
      alloy   = "1.13.1" # Alloy v1.20.1
      grafana = "13.5.0" # Grafana 13.2.3, grafana-community repo
    }
  }

  config         = merge(local.defaults, module.context.spec)
  chart_versions = merge(local.defaults.chart_versions, try(module.context.spec.chart_versions, {}))

  # Must match core-platform's Pod Identity bindings (monitoring/<writer>).
  namespace = "monitoring"

  observability = try(data.terraform_remote_state.observability.outputs, {})
  bucket        = try(local.observability.bucket_name, "observability-missing")
  prefixes = merge(
    { mimir = "mimir/", loki = "loki-", tempo = "tempo/" },
    try(local.observability.signal_prefixes, {}),
  )

  # Every object lands under <signal prefix><cluster name>/, the only path the
  # writer roles allow. Mimir's prefix may only be alphanumeric, so the cluster
  # name comes in as its tenant (objects at <prefix>/<tenant>/).
  template_vars = {
    cluster_name = local.cluster_name
    region       = local.region
    bucket       = local.bucket
    mimir_prefix = trimsuffix(local.prefixes.mimir, "/")
    loki_prefix  = "${local.prefixes.loki}${local.cluster_name}"
    tempo_prefix = "${local.prefixes.tempo}${local.cluster_name}"
    namespace    = local.namespace
  }
}
