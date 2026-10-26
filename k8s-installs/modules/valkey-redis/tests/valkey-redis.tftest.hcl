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

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.this[0].namespace == "valkey-operator" && helm_release.this[0].version == "0.4.1"
    error_message = "the Valkey operator installs the pinned chart into valkey-operator"
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
