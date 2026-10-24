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

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "vllm is per model: name the file vllm.<model slug>.yaml."
    }
    precondition {
      condition     = !local.config.enabled || (local.config.model != null && local.config.gpu != null)
      error_message = "spec.model (Hugging Face ID) and spec.gpu (GPU type) are required — Backstage fills both from the phoenix-model entity."
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
    name          = local.server
    model         = local.config.model
    replicas      = local.config.replicas
    maxModelLen   = local.config.max_model_len
    extraArgs     = local.config.extra_args
    image         = { repository = "vllm/vllm-openai", tag = local.config.image_tag }
    gpu           = { type = local.config.gpu, perReplica = local.config.gpus_per_replica }
    hfTokenSecret = local.hf_token_secret
    route = {
      hostname = local.hostname
      gateway  = { name = try(local.gateway.name, ""), namespace = try(local.gateway.namespace, "") }
      pool     = local.pool_name
    }
  })]

  depends_on = [helm_release.pool]
}
