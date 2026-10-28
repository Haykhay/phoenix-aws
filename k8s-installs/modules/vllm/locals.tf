locals {
  defaults = {
    enabled = true
    # Served model name; defaults to the weights unit's model.
    model = null
    # The model-weights version to serve, and the GPU type (Backstage fills both).
    version          = null
    gpu              = null
    replicas         = 1
    gpus_per_replica = 1
    max_model_len    = null
    extra_args       = []
    image_tag        = "v0.31.0"
    hardware         = "nvidia" # or neuron: must match the pool's accelerator
    # Neuron: tensor parallelism counts NeuronCores, not devices.
    tensor_parallel_size = null                                               # default: gpus_per_replica
    neuron_image_tag     = "0.24.0.1.1.0-neuronx-py313-sdk2.32.0-ubuntu24.04" # 2026-08-18, Neuron SDK 2.32
    pool_chart           = "v1.5.0"                                           # inferencepool chart + endpoint picker (InferencePool v1)
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "models"

  # One unit = one model: vllm.<model slug>.yaml
  slug      = coalesce(local.instance, "missing")
  server    = "vllm-${local.slug}"
  pool_name = "${local.server}-pool"

  gateway  = try(data.terraform_remote_state.istio.outputs.gateways.internal, null)
  hostname = "${local.slug}-${local.cluster_key}.${try(local.gateway.domain, "istio-missing")}"

  weights          = try(data.terraform_remote_state.weights.outputs, {})
  fsx              = try(data.terraform_remote_state.fsx.outputs, {})
  pool_accelerator = try(data.terraform_remote_state.gpu_pool.outputs.accelerator, "nvidia")
  hardware = {
    nvidia = {
      image       = { repository = "vllm/vllm-openai", tag = local.config.image_tag }
      accelerator = { resource = "nvidia.com/gpu", taint = "nvidia.com/gpu" }
      command     = [] # the image's entrypoint is the OpenAI server
    }
    neuron = {
      image       = { repository = "public.ecr.aws/neuron/pytorch-inference-vllm-neuronx", tag = local.config.neuron_image_tag }
      accelerator = { resource = "aws.amazon.com/neuron", taint = "aws.amazon.com/neuron" }
      # Its entrypoint runs whatever command it is given.
      command = ["python", "-m", "vllm.entrypoints.openai.api_server"]
    }
  }[local.config.hardware == "neuron" ? "neuron" : "nvidia"]

  served_name = coalesce(local.config.model, try(local.weights.model, null), local.slug)
  # Loading from FSx is minutes, not hours, but a 600B model still needs time.
  startup_seconds = max(1800, try(local.weights.size_gib, 0) * 6)
}
