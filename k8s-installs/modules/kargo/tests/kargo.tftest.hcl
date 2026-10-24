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
          cluster_security_group_id          = "sg-cluster-1"
          vpc_id                             = "vpc-123"
          node_subnet_ids                    = ["subnet-p1", "subnet-p2", "subnet-p3"]
          karpenter = {
            controller_role_arn = "arn:aws:iam::111111111111:role/vision-sandbox-euw1-1-karpenter-controller"
            node_role_name      = "vision-sandbox-euw1-1-karpenter-node"
            node_role_arn       = "arn:aws:iam::111111111111:role/vision-sandbox-euw1-1-karpenter-node"
            queue_name          = "vision-sandbox-euw1-1-karpenter"
            namespace           = "karpenter"
            service_account     = "karpenter"
          }
        }
        "2" = {
          cluster_name                       = "vision-sandbox-euw1-2-eks"
          cluster_endpoint                   = "https://DEF.gr7.eu-west-1.eks.amazonaws.com"
          cluster_certificate_authority_data = "Q0EtREFUQQ=="
          node_security_group_id             = "sg-456"
          cluster_security_group_id          = "sg-cluster-2"
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

override_data {
  target = module.management_cluster.data.terraform_remote_state.core_platform
  values = {
    outputs = {
      clusters = {
        "1" = {
          cluster_name                       = "vision-sandbox-euw1-1-eks"
          cluster_endpoint                   = "https://ABC.gr7.eu-west-1.eks.amazonaws.com"
          cluster_certificate_authority_data = "Q0EtREFUQQ=="
          cluster_kms_key_arn                = "arn:aws:kms:eu-west-1:111111111111:key/1234"
          node_security_group_id             = "sg-123"
          cluster_security_group_id          = "sg-cluster-1"
          vpc_id                             = "vpc-123"
          node_subnet_ids                    = ["subnet-p1", "subnet-p2", "subnet-p3"]
          karpenter = {
            controller_role_arn = "arn:aws:iam::111111111111:role/vision-sandbox-euw1-1-karpenter-controller"
            node_role_name      = "vision-sandbox-euw1-1-karpenter-node"
            node_role_arn       = "arn:aws:iam::111111111111:role/vision-sandbox-euw1-1-karpenter-node"
            queue_name          = "vision-sandbox-euw1-1-karpenter"
            namespace           = "karpenter"
            service_account     = "karpenter"
          }
        }
        "2" = {
          cluster_name                       = "vision-sandbox-euw1-2-eks"
          cluster_endpoint                   = "https://DEF.gr7.eu-west-1.eks.amazonaws.com"
          cluster_certificate_authority_data = "Q0EtREFUQQ=="
          node_security_group_id             = "sg-456"
          cluster_security_group_id          = "sg-cluster-2"
          vpc_id                             = "vpc-123"
          karpenter                          = null
        }
      }
    }
  }
}

override_data {
  target = module.management_cluster.data.terraform_remote_state.dns
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

override_data {
  target = data.terraform_remote_state.management[0]
  values = {
    outputs = {
      remote_kubeconfig_secret = "acme/vision-sandbox/kargo/remote-kubeconfig"
    }
  }
}

override_data {
  target = data.aws_secretsmanager_secret_version.remote_kubeconfig[0]
  values = {
    secret_string = "apiVersion: v1\nkind: Config\n"
  }
}

run "management_mode_on_cluster_1" {
  command = plan

  assert {
    condition     = local.mode == "management" && helm_release.this[0].version == "1.11.2" && helm_release.this[0].namespace == "kargo"
    error_message = "cluster 1 (spec.management_cluster default) runs the full Kargo"
  }
  assert {
    condition     = aws_secretsmanager_secret.admin[0].name == "acme/vision-sandbox/kargo/admin" && aws_secretsmanager_secret.remote_kubeconfig[0].name == "acme/vision-sandbox/kargo/remote-kubeconfig"
    error_message = "management secrets live under <organisation>/<env_id>/kargo/"
  }
  assert {
    condition     = yamldecode(helm_release.route[0].values[0]).hostname == "kargo.internal.sandbox.vision.example.com" && yamldecode(helm_release.route[0].values[0]).service.name == "kargo-api"
    error_message = "the Kargo API/UI is an HTTPRoute on istio's internal gateway"
  }
  assert {
    condition     = length(aws_security_group_rule.management_api_access) == 0 && length(kubernetes_secret_v1.kargo_management_kubeconfig) == 0
    error_message = "the management cluster opens nothing to itself and mounts no remote kubeconfig"
  }
}

run "spoke_mode_on_cluster_2" {
  command = plan

  variables {
    config_file = "tests/fixtures/spoke.yaml"
  }

  assert {
    condition     = local.mode == "spoke" && local.shard == "vision-sandbox-2" && length(aws_iam_role.kargo_controller) == 0 && length(helm_release.route) == 0
    error_message = "cluster 2 runs only a shard controller: no warehouse role, no API route"
  }
  assert {
    condition     = aws_security_group_rule.management_api_access[0].security_group_id == "sg-cluster-1" && aws_security_group_rule.management_api_access[0].source_security_group_id == "sg-456"
    error_message = "the spoke's nodes (and only they) may reach the management cluster's API"
  }
  assert {
    condition     = kubernetes_secret_v1.kargo_management_kubeconfig[0].metadata[0].name == "kargo-management-kubeconfig"
    error_message = "the spoke mounts the management cluster's kubeconfig"
  }
}

run "spoke_without_management_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/spoke.yaml"
  }

  override_data {
    target = data.terraform_remote_state.management[0]
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
    condition     = length(helm_release.this) + length(aws_iam_role.kargo_controller) + length(aws_secretsmanager_secret.admin) == 0
    error_message = "spec.enabled: false creates nothing"
  }
}
