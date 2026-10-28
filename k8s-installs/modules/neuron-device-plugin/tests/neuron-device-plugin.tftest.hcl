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
    condition     = helm_release.plugin[0].version == "1.10.0" && helm_release.plugin[0].namespace == "kube-system"
    error_message = "the Neuron chart is pinned"
  }
  assert {
    condition     = contains([for t in yamldecode(helm_release.plugin[0].values[0]).devicePlugin.tolerations : t.key], "aws.amazon.com/neuron")
    error_message = "the device plugin runs on Neuron nodes despite their taint"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.monitor[0].values[0]).podAnnotations["prometheus.io/scrape"] == "true",
      yamldecode(helm_release.monitor[0].values[0]).podAnnotations["prometheus.io/port"] == "8000",
      yamldecode(helm_release.monitor[0].values[0]).nodeSelector == { "phoenix/accelerator" = "neuron" },
    ])
    error_message = "neuron-monitor runs on Neuron nodes and Alloy scrapes it"
  }
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.plugin) + length(helm_release.monitor) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
