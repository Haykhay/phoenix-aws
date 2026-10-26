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

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.server[0].name == "vllm-llama-3-8b" && helm_release.server[0].namespace == "models"
    error_message = "one vLLM release per model, named after the instance, in models"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.server[0].values[0]).model == "meta-llama/Llama-3.1-8B-Instruct",
      yamldecode(helm_release.server[0].values[0]).image.tag == "v0.31.0",
      yamldecode(helm_release.server[0].values[0]).gpu.type == "l4",
      yamldecode(helm_release.server[0].values[0]).gpu.perReplica == 1,
      yamldecode(helm_release.server[0].values[0]).hfTokenSecret == "acme/research-sandbox/models/hf-token",
    ])
    error_message = "the model runs on its GPU pool with the platform's pinned vLLM; HF token from the environment's models path"
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

run "model_required" {
  command = plan

  variables {
    config_file = "tests/fixtures/vllm.no-model.yaml"
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
