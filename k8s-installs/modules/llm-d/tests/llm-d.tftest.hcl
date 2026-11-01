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

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.lws[0].version == "0.11.1" && helm_release.lws[0].repository == "oci://registry.k8s.io/lws/charts"
    error_message = "the LeaderWorkerSet controller is pinned"
  }
  assert {
    condition     = output.version == "v0.10.0"
    error_message = "the pinned llm-d release is reported for vllm's option checks"
  }
  assert {
    condition = toset(output.supported_options) == toset([
      "routing", "kv_offload", "flow_control", "autoscaling", "multi_node", "pd_disaggregation", "wide_ep",
    ])
    error_message = "every option with a well-lit path in the pinned release; batch is experimental in v0.10.0, so deferred"
  }
  assert {
    condition     = helm_release.keda[0].version == "2.21.0" && helm_release.keda[0].namespace == "keda"
    error_message = "KEDA, pinned, scales models with autoscaling on"
  }
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.lws) + length(helm_release.keda) == 0 && length(output.supported_options) == 0
    error_message = "spec.enabled: false installs nothing and offers no options"
  }
}
