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
          cluster_name                       = "vision-sandbox-euw1-1-eks"
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
          public_zone_name   = "sandbox.vision.example.com"
          internal_zone_id   = "Z1INT"
          internal_zone_name = "internal.sandbox.vision.example.com"
        }
      }
    }
  }
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.this[0].version == "2.6.0" && helm_release.this[0].namespace == "external-secrets"
    error_message = "external-secrets installs the pinned chart into its own namespace"
  }
  assert {
    condition     = aws_eks_pod_identity_association.this[0].namespace == "external-secrets" && aws_eks_pod_identity_association.this[0].service_account == "external-secrets"
    error_message = "the Pod Identity association binds the chart's service account"
  }
  assert {
    condition     = aws_iam_role.this[0].name == "vision-sandbox-euw1-1-external-secrets"
    error_message = "the role is named <name_prefix>-external-secrets"
  }
}

run "pod_identity_scoped" {
  command = plan

  assert {
    condition     = local.secrets_manager_arns == ["arn:aws:secretsmanager:eu-west-1:111111111111:secret:acme/vision-sandbox/*"]
    error_message = "Secrets Manager access is limited to <organisation>/<env_id>/ in the unit's account and region"
  }
  assert {
    condition     = local.ssm_parameter_arns == ["arn:aws:ssm:eu-west-1:111111111111:parameter/acme/vision-sandbox/*"]
    error_message = "SSM access is limited to /<organisation>/<env_id>/ in the unit's account and region"
  }
  assert {
    condition     = length(local.kms_key_arns) == 1 && local.kms_key_arns[0] == "arn:aws:kms:eu-west-1:111111111111:key/1234"
    error_message = "decrypt is allowed with the cluster's KMS key by default"
  }
}

run "personal_env_names_fit" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "vision-sandbox-jdoe-euw1-1-external-secrets" && length(aws_iam_role.this[0].name) <= 64
    error_message = "a personal environment's role name fits IAM's 64 characters"
  }
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.this) + length(aws_iam_role.this) + length(aws_eks_pod_identity_association.this) == 0
    error_message = "spec.enabled: false creates nothing"
  }
}
