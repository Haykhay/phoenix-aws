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
    condition     = helm_release.this[0].version == "1.21.1" && helm_release.this[0].namespace == "external-dns"
    error_message = "external-dns installs the pinned chart into its own namespace"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).txtOwnerId == "research-sandbox-euw1-1" && yamldecode(helm_release.this[0].values[0]).policy == "upsert-only"
    error_message = "records are owned per cluster and never deleted by default"
  }
}

run "zone_scoped_iam" {
  command = plan

  assert {
    condition     = length(local.route53_zone_ids) == 2 && contains(local.route53_zone_ids, "Z1PUB") && contains(local.route53_zone_ids, "Z1INT")
    error_message = "by default only the cluster's own public and internal zone"
  }
  assert {
    condition     = toset(yamldecode(helm_release.this[0].values[0]).extraArgs) == toset([for z in local.route53_zone_ids : "--zone-id-filter=${z}"])
    error_message = "the zones it reconciles (--zone-id-filter; the chart has no zoneIdFilters value) are the zones its IAM policy covers"
  }
}

run "extra_zone_on_request" {
  command = plan

  variables {
    config_file = "tests/fixtures/two_zones.yaml"
  }

  override_data {
    target = module.cluster.data.terraform_remote_state.dns
    values = {
      outputs = {
        zones = {
          "zone-1" = { public_zone_id = "Z1PUB", public_zone_name = "a.example.com", internal_zone_id = "Z1INT", internal_zone_name = "internal.a.example.com" }
          "zone-2" = { public_zone_id = "Z2PUB", public_zone_name = "b.example.com", internal_zone_id = "Z2INT", internal_zone_name = "internal.b.example.com" }
        }
      }
    }
  }

  assert {
    condition     = length(local.route53_zone_ids) == 4 && contains(local.route53_zone_ids, "Z2INT")
    error_message = "naming zones extends both the filter and the IAM scope"
  }
}

run "personal_env_names_fit" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "research-sandbox-jdoe-euw1-1-external-dns" && length(aws_iam_role.this[0].name) <= 64
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
    condition     = length(helm_release.this) + length(aws_iam_role.this) == 0
    error_message = "spec.enabled: false creates nothing"
  }
}
