# Composition of the llm-d options (spec.llm_d), from llm-d v0.10.0's guides.
# Router: llm-d-router-gateway with a picker config built from the options.
# Server: values.llmD, rendered by manifests/vllm/templates/llm-d.yaml.
locals {
  efa_on = local.pool_efa && (local.llm_d.multi_node || local.llm_d.pd_disaggregation || local.llm_d.wide_ep)
  nodes  = local.llm_d.multi_node ? local.config.nodes_per_replica : 1
  gpus   = local.config.gpus_per_replica

  # --- Picker ---------------------------------------------------------------
  # routing adds prefix-cache affinity to the load scorers (flow-control guide's set).
  scorers = concat(
    [for p in [{ pluginRef = "prefix-cache-scorer", weight = 3 }] : p if local.llm_d.routing],
    [{ pluginRef = "queue-scorer", weight = 2 }, { pluginRef = "kv-cache-utilization-scorer", weight = 2 }],
  )
  profiles = concat(
    [for p in [
      { name = "prefill", plugins = concat([{ pluginRef = "prefill-filter" }], local.scorers) },
      { name = "decode", plugins = [{ pluginRef = "decode-filter" }, { pluginRef = "active-request-scorer" }] },
    ] : p if local.llm_d.pd_disaggregation],
    [for p in [{ name = "default", plugins = local.scorers }] : p if !local.llm_d.pd_disaggregation],
  )
  profile_plugins = distinct(flatten([for p in local.profiles : [for r in p.plugins : r.pluginRef]]))
  extra_plugins = concat(
    [for p in [
      { type = "always-disagg-pd-decider" },
      { type = "disagg-profile-handler", parameters = { deciders = { prefill = "always-disagg-pd-decider" } } },
    ] : p if local.llm_d.pd_disaggregation],
    [for p in [
      { type = "round-robin-fairness-policy" },
      { type = "fcfs-ordering-policy" },
      { type = "concurrency-detector", parameters = { maxConcurrency = 132, concurrencyMode = "requests", headroom = 0 } },
    ] : p if local.llm_d.flow_control],
  )
  # Flow control, as the flow-control guide: requests queue in the picker by
  # priority band; fairness within a band is per x-gateway-inference-fairness-id
  # (Task 10 sets it from the caller).
  band = { fairnessPolicyRef = "round-robin-fairness-policy", orderingPolicyRef = "fcfs-ordering-policy" }
  epp_config = yamlencode(merge({
    apiVersion         = "llm-d.ai/v1alpha1"
    kind               = "EndpointPickerConfig"
    plugins            = concat(local.extra_plugins, [for t in local.profile_plugins : { type = t }])
    schedulingProfiles = local.profiles
    }, [for f in [{
      featureGates = ["flowControl"]
      flowControl = {
        maxBytes           = "10Gi"
        maxRequests        = "1k"
        defaultRequestTTL  = "60s"
        saturationDetector = { pluginRef = "concurrency-detector" }
        priorityBands = [
          merge(local.band, { priority = 100, maxRequests = "500" }),
          merge(local.band, { priority = 0, maxRequests = "200" }),
          merge(local.band, { priority = -10, maxRequests = "50" }),
        ]
      }
  }] : f if local.llm_d.flow_control]...))

  # --- Server ---------------------------------------------------------------
  nixl = {
    kv_connector              = "NixlConnector"
    kv_role                   = "kv_both"
    kv_connector_extra_config = { backends = [local.efa_on ? "LIBFABRIC" : "UCX"] }
  }
  offload = {
    kv_connector              = "OffloadingConnector"
    kv_role                   = "kv_both"
    kv_connector_extra_config = { cpu_bytes_to_use = local.config.kv_offload_cpu_gib * 1073741824 }
  }
  kv_transfer = (
    local.llm_d.pd_disaggregation && local.llm_d.kv_offload ? jsonencode({
      kv_connector              = "MultiConnector", kv_role = "kv_both"
      kv_connector_extra_config = { connectors = [local.nixl, local.offload] }
    }) :
    local.llm_d.pd_disaggregation ? jsonencode(local.nixl) :
    local.llm_d.kv_offload ? jsonencode(local.offload) : ""
  )

  # LeaderWorkerSet sets LWS_* in every pod of a group; workers add --headless.
  parallel_args = (
    local.llm_d.wide_ep ? [
      "--enable-expert-parallel",
      "--tensor-parallel-size=1",
      "--data-parallel-size=$((LWS_GROUP_SIZE * ${local.gpus}))",
      "--data-parallel-size-local=${local.gpus}",
      "--data-parallel-address=$LWS_LEADER_ADDRESS",
      "--data-parallel-rpc-port=5555",
      "--data-parallel-start-rank=$((LWS_WORKER_INDEX * ${local.gpus}))",
    ] :
    local.llm_d.multi_node ? [
      "--tensor-parallel-size=${local.gpus}",
      "--pipeline-parallel-size=${local.nodes}",
      "--nnodes=$LWS_GROUP_SIZE",
      "--node-rank=$LWS_WORKER_INDEX",
      "--master-addr=$LWS_LEADER_ADDRESS",
    ] :
    ["--tensor-parallel-size=${coalesce(local.config.tensor_parallel_size, local.gpus)}"]
  )
  # ponytail: extra_args are joined into a shell line; an arg containing spaces breaks it.
  common_args = concat(
    ["--model=${local.cache_path}", "--served-model-name=${local.served_name}"],
    local.config.max_model_len == null ? [] : ["--max-model-len=${local.config.max_model_len}"],
    local.parallel_args,
    local.kv_transfer == "" ? [] : ["--kv-transfer-config=\"$KV_TRANSFER_CONFIG\""],
    local.config.extra_args,
  )
  # P/D: decode listens on 8200 behind the routing sidecar on 8000, as the guide.
  sets = local.llm_d.pd_disaggregation ? [
    { name = "${local.server}-prefill", role = "prefill", replicas = local.config.prefill_replicas, nodes = local.nodes, port = 8000, sidecar = false, args = concat(local.common_args, ["--port=8000"]) },
    { name = "${local.server}-decode", role = "decode", replicas = local.config.decode_replicas, nodes = local.nodes, port = 8200, sidecar = true, args = concat(local.common_args, ["--port=8200"]) },
    ] : [
    { name = local.server, role = "", replicas = local.llm_d.autoscaling ? max(1, local.config.min_replicas) : local.config.replicas, nodes = local.nodes, port = 8000, sidecar = false, args = concat(local.common_args, ["--port=8000"]) },
  ]
  scaled = local.sets[length(local.sets) - 1] # decode under P/D

  llm_d_values = {
    sets             = local.sets
    kvTransferConfig = local.kv_transfer
    efa              = { enabled = local.efa_on, interfaces = local.config.efa_interfaces }
    # Host memory for offloaded KV plus vLLM's own; Karpenter sizes the node from it.
    memoryRequest = local.llm_d.kv_offload ? "${local.config.kv_offload_cpu_gib + 32}Gi" : ""
    sidecarImage  = "ghcr.io/llm-d/llm-d-router-disagg-sidecar:${local.config.disagg_sidecar_tag}"
    # KEDA on the router's running-request count, read from Mimir. Never to zero.
    autoscaling = local.llm_d.autoscaling ? {
      target           = local.scaled.name
      targetKind       = local.nodes > 1 ? "LeaderWorkerSet" : "Deployment"
      targetApiVersion = local.nodes > 1 ? "leaderworkerset.x-k8s.io/v1" : "apps/v1"
      minReplicas      = max(1, local.config.min_replicas)
      maxReplicas      = max(1, local.config.min_replicas, local.config.max_replicas)
      serverAddress    = "http://mimir-gateway.monitoring.svc/prometheus"
      query            = "sum(llm_d_epp_request_running{model_name=\"${local.served_name}\"})"
      threshold        = tostring(local.config.autoscale_target)
    } : null
  }
}

resource "helm_release" "router" {
  count      = local.config.enabled && local.llm_d_any ? 1 : 0
  name       = local.pool_name # the InferencePool takes the release name: the HTTPRoute is unchanged
  repository = "oci://ghcr.io/llm-d/charts"
  chart      = "llm-d-router-gateway"
  version    = local.config.router_chart
  namespace  = local.namespace

  values = [yamlencode({
    provider  = { name = "istio" }
    httpRoute = { create = false } # the server chart owns the route
    router = {
      epp = {
        replicas            = 1
        pluginsConfigFile   = "phoenix.yaml"
        pluginsCustomConfig = { "phoenix.yaml" = local.epp_config }
        resources           = { requests = { cpu = "500m", memory = "1Gi" }, limits = { memory = "2Gi" } }
        # grafana-stack's Alloy scrapes it; autoscaling reads it back from Mimir.
        podAnnotations = { "prometheus.io/scrape" = "true", "prometheus.io/port" = "9090" }
      }
      inferencePool = { failureMode = "FailOpen" }
      modelServers = {
        type        = "vllm"
        matchLabels = { app = local.server }
        targetPorts = [{ number = 8000 }]
      }
    }
  })]

  depends_on = [terraform_data.validation]
}
