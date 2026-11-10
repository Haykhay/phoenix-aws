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

run "driver_disabled_dcgm_on" {
  command = plan

  assert {
    condition     = helm_release.this[0].version == "v26.7.1" && helm_release.this[0].namespace == "gpu-operator"
    error_message = "the GPU operator installs the pinned chart into gpu-operator"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.this[0].values[0]).driver.enabled == false,
      yamldecode(helm_release.this[0].values[0]).toolkit.enabled == false,
      yamldecode(helm_release.this[0].values[0]).devicePlugin.enabled == true,
      yamldecode(helm_release.this[0].values[0]).dcgmExporter.enabled == true,
    ])
    error_message = "AL2023 NVIDIA AMIs ship driver and toolkit; the operator adds the device plugin and DCGM exporter"
  }
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.this) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}

run "operator_renders_slicing_config" {
  command = plan

  assert {
    condition = alltrue([
      try(yamldecode(helm_release.this[0].values[0]).devicePlugin.config.create, false) == true,
      try(yamldecode(helm_release.this[0].values[0]).devicePlugin.config.name, "") == "time-slicing",
      try(yamldecode(helm_release.this[0].values[0]).devicePlugin.config.default, "") == "none",
      try(keys(yamldecode(helm_release.this[0].values[0]).devicePlugin.config.data), []) == ["none", "ts-2", "ts-4"],
      try(yamldecode(yamldecode(helm_release.this[0].values[0]).devicePlugin.config.data.none), null) == { version = "v1" },
    ])
    error_message = "the device plugin gets profiles ts-2 and ts-4 (picked per node by its nvidia.com/device-plugin.config label) and no sharing by default"
  }
  assert {
    condition = alltrue([for n in [2, 4] : try(yamldecode(yamldecode(helm_release.this[0].values[0]).devicePlugin.config.data["ts-${n}"]), null) == {
      version = "v1"
      sharing = { timeSlicing = { failRequestsGreaterThanOne = true, resources = [{ name = "nvidia.com/gpu", replicas = n }] } }
    }])
    error_message = "profile ts-<n> shares each nvidia.com/gpu n ways and refuses a pod asking for more than one share"
  }
}

run "no_slicing_profiles_no_config" {
  command = plan

  variables {
    config_file = "tests/fixtures/no-slicing.yaml"
  }

  assert {
    condition     = try(yamldecode(helm_release.this[0].values[0]).devicePlugin.config, null) == null && yamldecode(helm_release.this[0].values[0]).devicePlugin.enabled == true
    error_message = "with no profiles the device plugin runs as before"
  }
}
