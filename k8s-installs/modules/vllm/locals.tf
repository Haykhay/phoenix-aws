locals {
  defaults = {
    enabled = true
    # From Backstage's phoenix-model entity: Hugging Face model ID and GPU type.
    model            = null
    gpu              = null
    replicas         = 1
    gpus_per_replica = 1
    max_model_len    = null
    extra_args       = []
    image_tag        = "v0.31.0"
    pool_chart       = "v1.5.0" # inferencepool chart + endpoint picker (InferencePool v1)
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "models"

  # One unit = one model: vllm.<model slug>.yaml
  slug      = coalesce(local.instance, "missing")
  server    = "vllm-${local.slug}"
  pool_name = "${local.server}-pool"

  gateway  = try(data.terraform_remote_state.istio.outputs.gateways.internal, null)
  hostname = "${local.slug}-${local.cluster_key}.${try(local.gateway.domain, "istio-missing")}"

  # Gated models need a Hugging Face token; optional otherwise.
  hf_token_secret = "${local.organisation}/${local.environment}/models/hf-token"
}
