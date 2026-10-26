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
    condition     = helm_release.this[0].version == "v1.20.2" && helm_release.this[0].namespace == "cert-manager"
    error_message = "cert-manager installs the pinned chart into its own namespace"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).crds.enabled == true && yamldecode(helm_release.this[0].values[0]).config.enableGatewayAPI == false
    error_message = "CRDs on; Gateway API integration off, so cert-manager does not wait on istio's CRDs (istio waits on cert-manager)"
  }
  assert {
    condition     = aws_eks_pod_identity_association.this[0].service_account == "cert-manager" && aws_iam_role.this[0].name == "research-sandbox-euw1-1-cert-manager"
    error_message = "Pod Identity binds cert-manager/cert-manager to <name_prefix>-cert-manager"
  }
}

run "issuers_use_cluster_zone" {
  command = plan

  assert {
    condition = alltrue([
      yamldecode(helm_release.cluster_issuers[0].values[0]).publicZoneId == "Z1PUB",
      yamldecode(helm_release.cluster_issuers[0].values[0]).internalZoneName == "internal.sandbox.research.example.com",
      yamldecode(helm_release.cluster_issuers[0].values[0]).acmeEmail == "",
    ])
    error_message = "the ACME issuers solve DNS-01 in the cluster's own zones; no email unless one is set"
  }
  assert {
    condition     = length(local.hosted_zone_arns) == 2 && contains(local.hosted_zone_arns, "arn:aws:route53:::hostedzone/Z1INT")
    error_message = "Route53 write access is limited to the cluster's two zones"
  }
}

run "personal_env_names_fit" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  assert {
    condition     = length(aws_iam_role.this[0].name) <= 64
    error_message = "a personal environment's role name fits IAM's 64 characters"
  }
}

run "no_dns_rejected" {
  command = plan

  override_data {
    target = module.cluster.data.terraform_remote_state.dns
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
    condition     = length(helm_release.this) + length(helm_release.cluster_issuers) + length(aws_iam_role.this) == 0
    error_message = "spec.enabled: false creates nothing"
  }
}
