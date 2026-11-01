locals {
  defaults = {
    enabled = true
    # The group's environment holding the observability unit (core-platform
    # binds the same one).
    observability_environment = "shared"
    # Model-serving dashboards and alerts, and kube-state-metrics for them.
    model_serving = true
    chart_versions = {
      mimir   = "6.2.1"  # Mimir 3.2.1 — ingest storage with the chart's own Kafka
      loki    = "7.3.0"  # Loki 3.6.12
      tempo   = "3.1.0"  # Tempo 3.1.0, grafana-community repo
      alloy   = "1.13.1" # Alloy v1.20.1
      grafana = "13.5.0" # Grafana 13.2.3, grafana-community repo
      # prometheus-community, 2026-09-26: pod start times and Pending reasons
      kube_state_metrics = "8.6.0"
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

  # llm-d's published dashboards, vendored unmodified from llm-d v0.10.0
  # (guides/recipes/observability/grafana/dashboards/). Their DS_PROMETHEUS
  # data source variable picks the default, Mimir; each gets a stable uid.
  llm_d_dashboards = ["llm-d-vllm-overview", "llm-d-inference-gateway", "llm-d-performance-kv-cache", "llm-d-failure-saturation-dashboard"]
  dashboards = merge(
    { "model-serving" = { json = file("${path.module}/manifests/dashboards/model-serving.json") } },
    { for n in local.llm_d_dashboards : n => {
      json = jsonencode(merge(
        jsondecode(file("${path.module}/manifests/dashboards/llm-d/${n}.json")),
        { uid = trimsuffix(n, "-dashboard"), id = null },
      ))
    } },
  )
  model_serving_values = yamlencode({
    dashboardProviders = {
      "model-serving.yaml" = {
        apiVersion = 1
        providers = [{
          name    = "model-serving", folder = "Model serving", type = "file", disableDeletion = true
          options = { path = "/var/lib/grafana/dashboards/model-serving" }
        }]
      }
    }
    dashboards = { "model-serving" = local.dashboards }
    alerting = {
      "model-serving.yaml" = yamldecode(templatefile("${path.module}/manifests/model-serving-alerts.yaml.tpl", {
        owner        = try(module.context.config.tags["owner.team"], "unknown")
        cluster_name = local.cluster_name
      }))
    }
  })
}
