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
          cluster_kms_key_arn                = "arn:aws:kms:eu-west-1:111111111111:key/1234"
          node_security_group_id             = "sg-123"
          vpc_id                             = "vpc-123"
          karpenter                          = null
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

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.this[0].name == "cluster-config" && helm_release.this[0].namespace == "kube-system"
    error_message = "cluster-config installs into kube-system"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).tags.Project == "Phoenix" && yamldecode(helm_release.this[0].values[0]).tags.Cluster == "1"
    error_message = "the gp3 StorageClass tags EBS volumes with the unit's tags, including Cluster"
  }
}

run "name_prefix_includes_cluster" {
  command = plan

  assert {
    condition     = local.name_prefix == "research-sandbox-euw1-1"
    error_message = "name_prefix is <env_id>-<region code>-<cluster>"
  }
}

run "personal_prefix" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  assert {
    condition     = local.name_prefix == "research-sandbox-jdoe-euw1-1"
    error_message = "a personal environment's prefix carries the requester"
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
