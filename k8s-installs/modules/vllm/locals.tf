locals {
  defaults = {
    enabled = true
    # Served model name; defaults to the weights unit's model.
    model = null
    # The model-weights version to serve, and the GPU type (Backstage fills both).
    version           = null
    gpu               = null
    replicas          = 1
    nodes_per_replica = 1 # > 1 needs llm_d.multi_node
    # llm-d options, all off: off is the default path (vLLM + endpoint picker).
    llm_d = {
      routing           = false # prefix-cache, load and session aware scheduling
      kv_offload        = false # tiered KV cache (CPU, then local disk)
      flow_control      = false # multi-tenant QoS
      autoscaling       = false # SLO-aware; never to zero
      batch             = false
      multi_node        = false # LeaderWorkerSet; nodes_per_replica >= 2
      pd_disaggregation = false
      wide_ep           = false
    }
    gpus_per_replica = 1 # per node when multi_node
    # Per option (see README): autoscaling, pd_disaggregation, kv_offload, EFA.
    min_replicas       = 1
    max_replicas       = 4
    autoscale_target   = 16 # running requests per replica (llm-d's KEDA default)
    prefill_replicas   = 1
    decode_replicas    = 1
    kv_offload_cpu_gib = 100
    efa_interfaces     = 1
    router_chart       = "v0.11.0"                                # llm-d-router-gateway, ships with llm-d v0.10.0 (2026-09-29)
    disagg_sidecar_tag = "v0.11.0"                                # llm-d-router-disagg-sidecar, same release
    efa_image_tag      = "0.30.0-gpu-py312-cu130-ubuntu24.04-ec2" # AWS vLLM DLC with EFA, llm-d v0.10.0's aws-efa image
    max_model_len      = null
    extra_args         = []
    image_tag          = "v0.31.0"
    hardware           = "nvidia" # or neuron: must match the pool's accelerator
    # Neuron: tensor parallelism counts NeuronCores, not devices.
    tensor_parallel_size = null                                               # default: gpus_per_replica
    neuron_image_tag     = "0.24.0.1.1.0-neuronx-py313-sdk2.32.0-ubuntu24.04" # 2026-08-18, Neuron SDK 2.32
    pool_chart           = "v1.5.0"                                           # inferencepool chart + endpoint picker (InferencePool v1)
  }

  config    = merge(local.defaults, module.context.spec)
  llm_d     = merge(local.defaults.llm_d, try(module.context.spec.llm_d, {}))
  llm_d_on  = [for k, on in local.llm_d : k if on]
  llm_d_any = length(local.llm_d_on) > 0

  # Option rules, each one name; the plan fails naming every rule broken.
  llm_d_state = try(data.terraform_remote_state.llm_d.outputs, {})
  pool_efa    = try(data.terraform_remote_state.gpu_pool.outputs.efa, false)
  option_checks = {
    nvidia_only              = !local.llm_d_any || local.config.hardware == "nvidia"
    wide_ep_needs_multi_node = !local.llm_d.wide_ep || local.llm_d.multi_node
    multi_node_needs_nodes   = local.llm_d.multi_node == (local.config.nodes_per_replica >= 2)
    efa_required             = !(local.llm_d.multi_node || local.llm_d.pd_disaggregation || local.llm_d.wide_ep) || local.pool_efa
    llm_d_installed          = !local.llm_d_any || can(local.llm_d_state.supported_options)
    available_in_release     = length(setsubtract(local.llm_d_on, try(local.llm_d_state.supported_options, local.llm_d_on))) == 0
  }
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
