# IAM resources validate policy JSON, so the mocked document is a real (empty) policy.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  config_file = "tests/fixtures/vllm.llama-3-8b.yaml"
}

override_data {
  target = module.cluster.data.terraform_remote_state.core_platform
  values = {
    outputs = {
      clusters = {
        "1" = {
          cluster_name                       = "research-sandbox-euw1-1-eks"
          cluster_endpoint                   = "https://ABC.gr7.eu-west-1.eks.amazonaws.com"
          cluster_certificate_authority_data = "Q0EtREFUQQ=="
          cluster_kms_key_arn                = "arn:aws:kms:eu-west-1:111111111111:key/1234"
          node_security_group_id             = "sg-123"
          vpc_id                             = "vpc-123"
          node_subnet_ids                    = ["subnet-p1", "subnet-p2", "subnet-p3"]
          karpenter = {
            controller_role_arn = "arn:aws:iam::111111111111:role/research-sandbox-euw1-1-karpenter-controller"
            node_role_name      = "research-sandbox-euw1-1-karpenter-node"
            node_role_arn       = "arn:aws:iam::111111111111:role/research-sandbox-euw1-1-karpenter-node"
            queue_name          = "research-sandbox-euw1-1-karpenter"
            namespace           = "karpenter"
            service_account     = "karpenter"
          }
        }
      }
    }
  }
}

override_data {
  target = module.cluster.data.terraform_remote_state.dns
  values = {
    outputs = {
      zones = {
        "zone-1" = {
          public_zone_id     = "Z1PUB"
          public_zone_name   = "sandbox.research.example.com"
          internal_zone_id   = "Z1INT"
          internal_zone_name = "internal.sandbox.research.example.com"
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.istio
  values = {
    outputs = {
      gateways = {
        internal = { name = "istio-internal", namespace = "istio-system", domain = "internal.sandbox.research.example.com" }
        external = null
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.gpu_pool
  values = {
    outputs = {
      node_pool     = "gpu-l4"
      node_selector = { "phoenix/gpu" = "l4" }
    }
  }
}

override_data {
  target = data.terraform_remote_state.weights
  values = {
    outputs = {
      model      = "llama-3-1-8b"
      version    = "0123456789abcdef0123456789abcdef01234567"
      cache_path = "/models/llama-3-1-8b/0123456789abcdef0123456789abcdef01234567"
      size_gib   = 200
    }
  }
}

override_data {
  target = data.terraform_remote_state.fsx
  values = {
    outputs = {
      pvc_name   = "model-cache"
      mount_path = "/models"
      sub_path   = "weights"
    }
  }
}

override_data {
  target = data.terraform_remote_state.llm_d
  values = { outputs = {} }
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.server[0].name == "vllm-llama-3-8b" && helm_release.server[0].namespace == "models"
    error_message = "one vLLM release per model, named after the instance, in models"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).modelPath == "/models/llama-3-1-8b/0123456789abcdef0123456789abcdef01234567",
      yamldecode(helm_release.server[0].values[0]).servedName == "llama-3-1-8b",
      yamldecode(helm_release.server[0].values[0]).image.tag == "v0.31.0",
      yamldecode(helm_release.server[0].values[0]).gpu.type == "l4",
      yamldecode(helm_release.server[0].values[0]).gpu.perReplica == 1,
      !can(yamldecode(helm_release.server[0].values[0]).hfTokenSecret),
    ])
    error_message = "the model loads from the FSx cache at its pinned version, on its GPU pool, with the platform's pinned vLLM; no Hugging Face token"
  }
  assert {
    condition = yamldecode(helm_release.server[0].values[0]).cache == {
      claim = "model-cache", mountPath = "/models", subPath = "weights"
    }
    error_message = "the model-cache claim is mounted (read-only, in the chart) with subPath weights at /models"
  }
  assert {
    condition     = local.startup_seconds == 1800 && yamldecode(helm_release.server[0].values[0]).startupSeconds == 1800
    error_message = "the startup budget is max(1800, size_gib * 6) seconds"
  }
  assert {
    condition = alltrue([
      helm_release.pool[0].version == "v1.5.0",
      yamldecode(helm_release.pool[0].values[0]).provider.name == "istio",
      yamldecode(helm_release.pool[0].values[0]).inferencePool.modelServers.matchLabels.app == "vllm-llama-3-8b",
    ])
    error_message = "an InferencePool (with its endpoint picker) selects this model's pods, for istio"
  }
}

run "routes_through_inference_pool" {
  command = plan

  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).route.hostname == "llama-3-8b-1.internal.sandbox.research.example.com",
      yamldecode(helm_release.server[0].values[0]).route.gateway.name == "istio-internal",
      yamldecode(helm_release.server[0].values[0]).route.pool == helm_release.pool[0].name,
    ])
    error_message = "an HTTPRoute on istio's internal gateway sends <model>-<cluster>.<internal zone> to the InferencePool"
  }
}

run "two_models_do_not_collide" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.mistral-7b.yaml"
  }

  assert {
    condition = alltrue([
      helm_release.server[0].name == "vllm-mistral-7b",
      helm_release.pool[0].name != "vllm-llama-3-8b",
      yamldecode(helm_release.server[0].values[0]).route.hostname == "mistral-7b-1.internal.sandbox.research.example.com",
      yamldecode(helm_release.server[0].values[0]).gpu.perReplica == 2,
    ])
    error_message = "a second model gets its own release, pool and hostname"
  }
}

run "missing_gpu_pool_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "missing_istio_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.istio
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "version_required" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.no-version.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.off.yaml"
  }

  assert {
    condition     = length(helm_release.server) + length(helm_release.pool) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}

run "served_name_overrides" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.llama-3-8b-named.yaml"
  }

  assert {
    condition     = yamldecode(helm_release.server[0].values[0]).servedName == "llama-chat" && output.model == "llama-chat"
    error_message = "spec.model is the served model name when set"
  }
}

run "startup_budget_scales_with_size" {
  command = plan

  override_data {
    target = data.terraform_remote_state.weights
    values = {
      outputs = {
        model      = "llama-3-1-8b"
        version    = "0123456789abcdef0123456789abcdef01234567"
        cache_path = "/models/llama-3-1-8b/0123456789abcdef0123456789abcdef01234567"
        size_gib   = 1200
      }
    }
  }

  assert {
    condition     = local.startup_seconds == 7200
    error_message = "a 1200 GiB model gets 1200 * 6 seconds to start"
  }
}

run "version_mismatch_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.other-version.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "missing_weights_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.weights
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "missing_cache_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.fsx
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "prepull_on_model_pool" {
  command = plan

  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).prepull == true,
      yamldecode(helm_release.server[0].values[0]).gpu.type == "l4",
      yamldecode(helm_release.server[0].values[0]).image.tag == "v0.31.0",
    ])
    error_message = "a prepull DaemonSet pulls the serving image onto the model's pool (phoenix/gpu=l4) before the model starts"
  }
}

run "neuron_model" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.llama-neuron.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = {
      outputs = {
        node_pool     = "gpu-trn2"
        node_selector = { "phoenix/gpu" = "trn2" }
        accelerator   = "neuron"
      }
    }
  }

  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).image.repository == "public.ecr.aws/neuron/pytorch-inference-vllm-neuronx",
      yamldecode(helm_release.server[0].values[0]).image.tag == "0.24.0.1.1.0-neuronx-py313-sdk2.32.0-ubuntu24.04",
      yamldecode(helm_release.server[0].values[0]).accelerator.resource == "aws.amazon.com/neuron",
      yamldecode(helm_release.server[0].values[0]).accelerator.taint == "aws.amazon.com/neuron",
      yamldecode(helm_release.server[0].values[0]).gpu.perReplica == 4,
      yamldecode(helm_release.server[0].values[0]).tensorParallel == 16,
    ])
    error_message = "a Neuron model runs the pinned Neuron vLLM image, requests gpus_per_replica Neuron devices and tolerates their taint"
  }
}

run "hardware_pool_mismatch_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.llama-neuron.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "nvidia_by_default" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.server[0].values[0]).accelerator.resource == "nvidia.com/gpu" && yamldecode(helm_release.server[0].values[0]).tensorParallel == 1
    error_message = "models run on NVIDIA by default, tensor parallel across their GPUs"
  }
}

# llm-d options. The file-level llm-d override is "not installed": the
# default path must never need it.
run "no_options_needs_no_llm_d" {
  command = plan

  assert {
    condition     = alltrue(values(local.option_checks)) && !local.llm_d_any
    error_message = "a model with no llm-d options plans without llm-d"
  }
}

run "routing_allowed" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.routing.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "batch", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition     = alltrue(values(local.option_checks))
    error_message = "routing on NVIDIA with llm-d installed passes every rule"
  }
}

run "llm_d_not_installed_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.routing.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "invalid_combinations_rejected_wide_ep_alone" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.wide-ep-alone.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "batch", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  expect_failures = [terraform_data.validation]
}

run "invalid_combinations_rejected_routing_on_neuron" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.routing-neuron.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = { node_pool = "gpu-l4", node_selector = { "phoenix/gpu" = "l4" }, accelerator = "neuron" } }
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "batch", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  expect_failures = [terraform_data.validation]
}

run "invalid_combinations_rejected_pd_without_efa" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.pd.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "batch", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  expect_failures = [terraform_data.validation]
}

run "invalid_combinations_rejected_not_in_release" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.batch.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.9.0", supported_options = ["routing"] } }
  }

  expect_failures = [terraform_data.validation]
}

run "multi_node_needs_two_nodes" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.multi-node-one.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = { node_pool = "gpu-l4", node_selector = { "phoenix/gpu" = "l4" }, efa = true } }
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "batch", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  expect_failures = [terraform_data.validation]
}

run "multi_node_on_efa_pool_allowed" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.multi-node.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = { node_pool = "gpu-l4", node_selector = { "phoenix/gpu" = "l4" }, efa = true } }
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "batch", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition     = alltrue(values(local.option_checks))
    error_message = "multi-node over two nodes on an EFA pool passes every rule"
  }
}

# --- Task 9: composition ---------------------------------------------------

run "default_render_unchanged" {
  command = plan

  assert {
    condition = helm_release.server[0].values[0] == yamlencode({
      name           = "vllm-llama-3-8b"
      modelPath      = "/models/llama-3-1-8b/0123456789abcdef0123456789abcdef01234567"
      servedName     = "llama-3-1-8b"
      startupSeconds = 1800
      cache          = { claim = "model-cache", mountPath = "/models", subPath = "weights" }
      prepull        = true
      replicas       = 1
      maxModelLen    = null
      extraArgs      = []
      image          = { repository = "vllm/vllm-openai", tag = "v0.31.0" }
      command        = []
      accelerator    = { resource = "nvidia.com/gpu", taint = "nvidia.com/gpu" }
      tensorParallel = 1
      gpu            = { type = "l4", perReplica = 1 }
      route = {
        hostname = "llama-3-8b-1.internal.sandbox.research.example.com"
        gateway  = { name = "istio-internal", namespace = "istio-system" }
        pool     = "vllm-llama-3-8b-pool"
      }
    })
    error_message = "with no llm-d options the server renders exactly as the default path"
  }
  assert {
    condition     = length(helm_release.pool) == 1 && length(helm_release.router) == 0 && output.llm_d_options == []
    error_message = "the default path keeps the inferencepool chart and no llm-d router"
  }
}

run "option_routing" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.routing.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition = alltrue([
      length(helm_release.pool) == 0,
      helm_release.router[0].name == "vllm-routing-pool",
      helm_release.router[0].version == "v0.11.0",
      strcontains(helm_release.router[0].values[0], "prefix-cache-scorer"),
      yamldecode(helm_release.router[0].values[0]).provider.name == "istio",
      output.endpoint == "https://routing-1.internal.sandbox.research.example.com/v1",
      output.llm_d_options == ["routing"],
    ])
    error_message = "routing swaps in the llm-d router (same pool name, so the route and endpoint stay) with the prefix-cache scorer"
  }
}

run "option_kv_offload" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.kv-offload.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition     = jsondecode(yamldecode(helm_release.server[0].values[0]).llmD.kvTransferConfig).kv_connector == "OffloadingConnector"
    error_message = "kv_offload sets vLLM's OffloadingConnector"
  }
}

run "option_flow_control" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.flow.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition     = contains(yamldecode(local.epp_config).featureGates, "flowControl") && length(yamldecode(local.epp_config).flowControl.priorityBands) == 3
    error_message = "flow_control turns on the picker's flow control with priority bands"
  }
}

run "option_autoscaling" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.autoscale.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).llmD.autoscaling.minReplicas == 1,
      yamldecode(helm_release.server[0].values[0]).llmD.autoscaling.maxReplicas == 6,
      yamldecode(helm_release.server[0].values[0]).llmD.autoscaling.targetKind == "Deployment",
    ])
    error_message = "autoscaling never goes to zero (min_replicas 0 becomes 1)"
  }
}

run "option_multi_node" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.multi-node.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = { node_pool = "gpu-l4", node_selector = { "phoenix/gpu" = "l4" }, efa = true } }
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition = alltrue([
      length(yamldecode(helm_release.server[0].values[0]).llmD.sets) == 1,
      yamldecode(helm_release.server[0].values[0]).llmD.sets[0].nodes == 2,
      contains(yamldecode(helm_release.server[0].values[0]).llmD.sets[0].args, "--pipeline-parallel-size=2"),
      yamldecode(helm_release.server[0].values[0]).llmD.efa.enabled == true,
    ])
    error_message = "multi_node renders one LeaderWorkerSet of nodes_per_replica nodes, pipeline-parallel across them, over EFA"
  }
}

run "option_wide_ep_single_node" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.wide-ep-one.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = { node_pool = "gpu-l4", node_selector = { "phoenix/gpu" = "l4" }, efa = true } }
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  expect_failures = [terraform_data.validation]
}

run "option_pd_with_kv_offload" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.pd-kv.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = { node_pool = "gpu-h200", node_selector = { "phoenix/gpu" = "h200" }, efa = true } }
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition = alltrue([
      [for s in yamldecode(helm_release.server[0].values[0]).llmD.sets : s.role] == ["prefill", "decode"],
      [for s in yamldecode(helm_release.server[0].values[0]).llmD.sets : s.sidecar] == [false, true],
      jsondecode(yamldecode(helm_release.server[0].values[0]).llmD.kvTransferConfig).kv_connector == "MultiConnector",
      strcontains(yamldecode(helm_release.server[0].values[0]).llmD.kvTransferConfig, "LIBFABRIC"),
      strcontains(local.epp_config, "disagg-profile-handler"),
    ])
    error_message = "P/D renders prefill and decode sets (decode behind the routing sidecar), NIXL over EFA (LIBFABRIC) combined with offloading, and the picker's P/D profiles"
  }
}

run "wide_ep_600b_fixture" {
  command = plan

  variables {
    config_file = "tests/fixtures/llm-d/vllm.deepseek.yaml"
  }

  override_data {
    target = data.terraform_remote_state.gpu_pool
    values = { outputs = { node_pool = "gpu-h200", node_selector = { "phoenix/gpu" = "h200" }, efa = true, capacity_reservations = [{ id = "cr-0123" }] } }
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition = alltrue([
      alltrue(values(local.option_checks)),
      [for s in yamldecode(helm_release.server[0].values[0]).llmD.sets : s.nodes] == [2, 2],
      contains(yamldecode(helm_release.server[0].values[0]).llmD.sets[1].args, "--enable-expert-parallel"),
      contains(yamldecode(helm_release.server[0].values[0]).llmD.sets[1].args, "--data-parallel-size=$((LWS_GROUP_SIZE * 8))"),
      yamldecode(helm_release.server[0].values[0]).image.repository == "public.ecr.aws/deep-learning-containers/vllm",
      join(",", sort(output.llm_d_options)) == "multi_node,pd_disaggregation,routing,wide_ep",
    ])
    error_message = "the day-one ~600B MoE: wide EP over two-node prefill and decode groups, P/D and routing, EFA image, on a reserved EFA pool"
  }
}

# --- Task 10: access ----------------------------------------------------------

run "uat_allows_only_owner_and_consumers" {
  command = plan

  variables {
    config_file = "tests/fixtures/access/vllm.owner-only.yaml"
  }

  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).access.allowedCidrs == ["10.20.0.0/16"],
      yamldecode(helm_release.server[0].values[0]).access.gateway.name == "istio-internal",
      yamldecode(helm_release.server[0].values[0]).access.gateway.namespace == "istio-system",
      yamldecode(helm_release.server[0].values[0]).access.hostname == "owner-only-1.internal.sandbox.research.example.com",
    ])
    error_message = "on the internal gateway, this model's hostname is reachable from the owner's CIDRs only"
  }
}

run "shared_allows_consumers" {
  command = plan

  variables {
    config_file = "tests/fixtures/access/vllm.shared.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition     = yamldecode(helm_release.server[0].values[0]).access.allowedCidrs == ["10.20.0.0/16", "10.30.0.0/16", "10.31.0.0/16"]
    error_message = "approved consumers' CIDRs are allowed beside the owner's"
  }
}

run "consumer_header_overwritten" {
  command = plan

  variables {
    config_file = "tests/fixtures/access/vllm.shared.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition = alltrue([
      strcontains(local.consumer_lua, "headers:replace(\"x-phoenix-consumer\", who)"),
      strcontains(local.consumer_lua, "headers:replace(\"x-gateway-inference-fairness-id\", who)"),
      !strcontains(local.consumer_lua, ":add("),
      strcontains(local.consumer_lua, "{ \"research\", \"10.20.0.0/16\" }"),
      strcontains(local.consumer_lua, "{ \"quant-research\", \"10.31.0.0/16\" }"),
      yamldecode(helm_release.server[0].values[0]).access.consumerLua == local.consumer_lua,
    ])
    error_message = "the gateway sets x-phoenix-consumer (and flow control's fairness id) from the caller's CIDR, replacing whatever the client sent"
  }
}

run "consumers_only_uat_prod" {
  command = plan

  variables {
    config_file = "tests/fixtures/access/vllm.sandbox-shared.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "shared_forces_flow_control" {
  command = plan

  variables {
    config_file = "tests/fixtures/access/vllm.shared.yaml"
  }

  override_data {
    target = data.terraform_remote_state.llm_d
    values = { outputs = { version = "v0.10.0", supported_options = ["routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep"] } }
  }

  assert {
    condition     = local.llm_d.flow_control && contains(output.llm_d_options, "flow_control") && length(helm_release.router) == 1
    error_message = "a model shared with other teams in uat/prod always has flow control"
  }
}

run "oidc_option" {
  command = plan

  variables {
    config_file = "tests/fixtures/access/vllm.oidc.yaml"
  }

  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).access.oidc.issuer == "https://idp.example.com",
      yamldecode(helm_release.server[0].values[0]).access.oidc.jwksUri == "https://idp.example.com/jwks",
      yamldecode(helm_release.server[0].values[0]).access.oidc.audiences == ["phoenix-models"],
      yamldecode(helm_release.server[0].values[0]).access.oidc.consumerClaim == "azp",
      yamldecode(helm_release.server[0].values[0]).access.consumerLua == "",
    ])
    error_message = "with an issuer, RequestAuthentication validates tokens (JWKS) and the consumer comes from the token's azp claim"
  }
}
