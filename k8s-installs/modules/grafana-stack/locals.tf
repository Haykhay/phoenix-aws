locals {
  defaults = {
    enabled = true
    # The group's environment holding the observability unit (core-platform
    # binds the same one).
    observability_environment = "shared"
    # Model-serving dashboards and alerts, and kube-state-metrics for them.
    model_serving = true
    # Send a few series to the management cluster's Mimir (ADR-0011):
    # { remote_write_url = "https://metrics-<cluster>.<its internal zone>/api/v1/push",
    #   credentials_secret = Secrets Manager name, default <organisation>/<env_id>/global-metrics }
    global_metrics = null
    # This is the management cluster: receive those series behind an
    # authenticating proxy on the internal gateway, and show them globally.
    global_receiver = false
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

  # Cross-cluster metrics (ADR-0011). Only these series leave a cluster: GPU
  # use, inference load, gateway traffic, node pools and OpenCost's costs.
  global_allowlist = [
    "DCGM_FI_DEV_GPU_UTIL", "llm_d_epp_request_running", "istio_requests_total", "karpenter_nodes_allocatable",
    "node_total_hourly_cost", "node_cpu_hourly_cost", "node_ram_hourly_cost", "node_gpu_hourly_cost",
    "container_cpu_allocation", "container_memory_allocation_bytes", "container_gpu_allocation",
  ]
  global_on     = local.config.global_metrics != null
  global_url    = try(local.config.global_metrics.remote_write_url, "")
  global_secret = "${module.context.organisation}/${module.context.env_id}/global-metrics"
  send_secret   = coalesce(try(local.config.global_metrics.credentials_secret, null), local.global_secret)
  receiver_on   = local.config.global_receiver
  internal_gw   = try(data.terraform_remote_state.istio.outputs.gateways.internal, null)
  receiver_host = "metrics-${local.cluster_key}.${try(local.internal_gw.domain, "istio-missing")}"

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
    global_on    = local.global_on
    global_url   = local.global_url
    global_regex = join("|", local.global_allowlist)
    env_id       = module.context.env_id
    tier         = module.context.tier
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

  # OpenCost's metrics (the opencost component), on every cluster.
  cost_values = yamlencode({
    dashboardProviders = {
      "cost.yaml" = {
        apiVersion = 1
        providers = [{
          name    = "cost", folder = "Cost", type = "file", disableDeletion = true
          options = { path = "/var/lib/grafana/dashboards/cost" }
        }]
      }
    }
    dashboards = { cost = { cost = { json = file("${path.module}/manifests/dashboards/cost.json") } } }
  })

  # The receiver's Global folder: cost across clouds and clusters.
  global_values = yamlencode({
    dashboardProviders = {
      "global.yaml" = {
        apiVersion = 1
        providers = [{
          name    = "global", folder = "Global", type = "file", disableDeletion = true
          options = { path = "/var/lib/grafana/dashboards/global" }
        }]
      }
    }
    dashboards = { global = { "global-cost" = { json = file("${path.module}/manifests/dashboards/global-cost.json") } } }
  })

  # Alloy reads the write credential from its environment, never its config.
  global_env_values = yamlencode({
    alloy = {
      extraEnv = [for k in ["username", "password"] : {
        name      = "GLOBAL_METRICS_${upper(k)}"
        valueFrom = { secretKeyRef = { name = "global-metrics", key = k } }
      }]
    }
  })
}
