# One served model per unit: vLLM on the model's GPU pool, an InferencePool
# (with its endpoint picker) over its pods, and an HTTPRoute on istio's
# internal gateway. Needs the cluster's istio unit and the karpenter-nodepool
# unit for the model's GPU type.
data "terraform_remote_state" "istio" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/k8s/${local.cluster_key}/istio/terraform.tfstate"
  }
  defaults = {}
}

data "terraform_remote_state" "gpu_pool" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/k8s/${local.cluster_key}/karpenter-nodepool.${coalesce(local.config.gpu, "none")}/terraform.tfstate"
  }
  defaults = {}
}

# The model's weights, copied by model-weights.<slug> on this cluster.
data "terraform_remote_state" "weights" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/k8s/${local.cluster_key}/model-weights.${local.slug}/terraform.tfstate"
  }
  defaults = {}
}

# The read-only claim on the cluster's FSx model cache.
data "terraform_remote_state" "fsx" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/k8s/${local.cluster_key}/aws-fsx-csi-driver/terraform.tfstate"
  }
  defaults = {}
}

# The cluster's llm-d prerequisites: needed only when an llm-d option is on.
data "terraform_remote_state" "llm_d" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/k8s/${local.cluster_key}/llm-d/terraform.tfstate"
  }
  defaults = {}
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "vllm is per model: name the file vllm.<model slug>.yaml."
    }
    precondition {
      condition     = !local.config.enabled || (local.config.version != null && local.config.gpu != null)
      error_message = "spec.version (the model-weights version) and spec.gpu (GPU type) are required — Backstage fills both."
    }
    precondition {
      condition     = !local.config.enabled || contains(["nvidia", "neuron"], local.config.hardware)
      error_message = "spec.hardware must be nvidia or neuron."
    }
    precondition {
      condition     = !local.config.enabled || !can(data.terraform_remote_state.gpu_pool.outputs.node_pool) || local.config.hardware == local.pool_accelerator
      error_message = "spec.hardware is ${local.config.hardware} but pool gpu-${coalesce(local.config.gpu, "none")} is ${local.pool_accelerator}: pick a ${local.config.hardware} GPU type."
    }
    precondition {
      condition     = !local.config.enabled || alltrue(values(local.option_checks))
      error_message = "spec.llm_d is invalid; failing checks: ${join(", ", [for k, ok in local.option_checks : k if !ok])}. llm-d options need hardware nvidia and the cluster's llm-d unit; wide_ep needs multi_node; multi_node needs nodes_per_replica >= 2 (and the reverse); multi_node, pd_disaggregation and wide_ep need an EFA pool; options must be in llm-d ${try(local.llm_d_state.version, "(not installed)")}'s supported_options (${join(", ", try(local.llm_d_state.supported_options, []))})."
    }
    precondition {
      condition     = !local.config.enabled || can(local.weights.cache_path)
      error_message = "no weights for ${local.slug} on cluster ${local.cluster_key}: apply model-weights.${local.slug} first."
    }
    precondition {
      condition     = !local.config.enabled || !can(local.weights.version) || try(local.weights.version == local.config.version, false)
      error_message = "spec.version is ${coalesce(local.config.version, "unset")} but model-weights.${local.slug} copied ${try(local.weights.version, "nothing")}: apply that version's weights first, or pin the version it has."
    }
    precondition {
      condition     = !local.config.enabled || can(local.fsx.pvc_name)
      error_message = "no model cache claim on cluster ${local.cluster_key}: apply aws-fsx-csi-driver first."
    }
    precondition {
      condition     = !local.config.enabled || local.gateway != null
      error_message = "no istio internal gateway for cluster ${local.cluster_key}: apply the cluster's istio unit first."
    }
    precondition {
      condition     = !local.config.enabled || can(data.terraform_remote_state.gpu_pool.outputs.node_pool)
      error_message = "no GPU pool \"${coalesce(local.config.gpu, "none")}\" on cluster ${local.cluster_key}: apply karpenter-nodepool.${coalesce(local.config.gpu, "none")} first."
    }
  }
}

resource "helm_release" "pool" {
  count            = local.config.enabled ? 1 : 0
  name             = local.pool_name
  repository       = "oci://registry.k8s.io/gateway-api-inference-extension/charts"
  chart            = "inferencepool"
  version          = local.config.pool_chart
  namespace        = local.namespace
  create_namespace = true

  values = [yamlencode({
    inferencePool = {
      modelServers    = { matchLabels = { app = local.server } }
      targetPorts     = [{ number = 8000 }]
      modelServerType = "vllm"
    }
    provider = { name = "istio" }
    # The chart's default (4 CPU / 8Gi) is sized for large fleets.
    inferenceExtension = {
      resources = { requests = { cpu = "500m", memory = "1Gi" }, limits = { memory = "2Gi" } }
    }
  })]

  depends_on = [terraform_data.validation]
}

resource "helm_release" "server" {
  count     = local.config.enabled ? 1 : 0
  name      = local.server
  chart     = "${path.module}/manifests/vllm"
  namespace = local.namespace
  timeout   = 1800 # model download + load

  values = [yamlencode({
    name           = local.server
    modelPath      = try(local.weights.cache_path, "")
    servedName     = local.served_name
    startupSeconds = local.startup_seconds
    cache = {
      claim     = try(local.fsx.pvc_name, "")
      mountPath = try(local.fsx.mount_path, "")
      subPath   = try(local.fsx.sub_path, "")
    }
    prepull        = true
    replicas       = local.config.replicas
    maxModelLen    = local.config.max_model_len
    extraArgs      = local.config.extra_args
    image          = local.hardware.image
    command        = local.hardware.command
    accelerator    = local.hardware.accelerator
    tensorParallel = coalesce(local.config.tensor_parallel_size, local.config.gpus_per_replica)
    gpu            = { type = local.config.gpu, perReplica = local.config.gpus_per_replica }
    route = {
      hostname = local.hostname
      gateway  = { name = try(local.gateway.name, ""), namespace = try(local.gateway.namespace, "") }
      pool     = local.pool_name
    }
  })]

  depends_on = [helm_release.pool]
}
