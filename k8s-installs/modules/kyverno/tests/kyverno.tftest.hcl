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
    condition     = helm_release.kyverno[0].version == "3.8.1" && helm_release.kyverno_policies[0].namespace == "kyverno"
    error_message = "kyverno and its policies install with the pinned chart"
  }
  assert {
    condition     = yamldecode(helm_release.kyverno_policies[0].values[0]).environmentImagePolicy.allowedImagePatterns == ["111111111111.dkr.ecr.eu-west-1.amazonaws.com/*"]
    error_message = "by default only the group account's own ECR is an allowed image source"
  }
  assert {
    condition     = yamldecode(helm_release.kyverno_policies[0].values[0]).policyMode == "Audit"
    error_message = "policies start in Audit"
  }
}

run "bad_policy_mode_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/bad_mode.yaml"
  }

  expect_failures = [helm_release.kyverno_policies]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.kyverno) == 0 && length(helm_release.kyverno_policies) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
