mock_provider "aws" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  config_file = "tests/fixtures/default.yaml"
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
        }
      }
    }
  }
}

# Not used here; the cluster module reads it for every component.
override_data {
  target = module.cluster.data.terraform_remote_state.dns
  values = { outputs = {} }
}

override_data {
  target = data.terraform_remote_state.model_cache
  values = {
    outputs = {
      file_system_id      = "fs-0123456789abcdef0"
      dns_name            = "fs-0123456789abcdef0.fsx.eu-west-1.amazonaws.com"
      mount_name          = "abcdefgh"
      weights_path_prefix = "/weights"
    }
  }
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.driver[0].version == "1.18.0" && helm_release.driver[0].namespace == "kube-system"
    error_message = "the driver chart is pinned"
  }
  assert {
    condition     = yamldecode(helm_release.driver[0].values[0]).node.tolerateAllTaints == true
    error_message = "the node daemonset runs on every node, GPU (nvidia.com/gpu) and Neuron (aws.amazon.com/neuron) pools included"
  }
  assert {
    condition     = helm_release.volume[0].namespace == "models"
    error_message = "the claim lives where vLLM runs"
  }
}

run "volume_comes_from_state" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.volume[0].values[0]).fsx.volumeHandle == "fs-0123456789abcdef0"
    error_message = "the PV's csi.volumeHandle is the model cache's file system ID"
  }
  assert {
    condition     = yamldecode(helm_release.volume[0].values[0]).fsx.dnsName == "fs-0123456789abcdef0.fsx.eu-west-1.amazonaws.com" && yamldecode(helm_release.volume[0].values[0]).fsx.mountName == "abcdefgh"
    error_message = "volumeAttributes dnsname and mountname come from model-cache state"
  }
  assert {
    condition     = output.pvc_name == "model-cache" && output.mount_path == "/models" && output.sub_path == "weights"
    error_message = "vllm mounts claim model-cache, subPath weights, at /models"
  }
}

run "missing_model_cache_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.model_cache
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.driver) + length(helm_release.volume) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
