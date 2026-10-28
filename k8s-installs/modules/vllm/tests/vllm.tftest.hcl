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
