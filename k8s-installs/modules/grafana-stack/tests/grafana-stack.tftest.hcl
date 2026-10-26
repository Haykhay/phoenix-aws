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

override_data {
  target = data.terraform_remote_state.observability
  values = {
    outputs = {
      bucket_name     = "research-shared-euw1-observability-111111111111"
      signal_prefixes = { mimir = "mimir/", loki = "loki-", tempo = "tempo/", langfuse = "langfuse/" }
    }
  }
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition = alltrue([
      helm_release.mimir[0].version == "6.2.1",
      helm_release.loki[0].version == "7.3.0",
      helm_release.tempo[0].version == "3.1.0",
      helm_release.alloy[0].version == "1.13.1",
      helm_release.grafana[0].version == "13.5.0",
    ])
    error_message = "five releases, each on the pinned chart version"
  }
  assert {
    condition     = alltrue([for r in [helm_release.mimir[0], helm_release.loki[0], helm_release.tempo[0], helm_release.alloy[0], helm_release.grafana[0]] : r.namespace == "monitoring"])
    error_message = "everything installs into monitoring"
  }
}

run "bindings_match_core_platform" {
  command = plan

  assert {
    condition = alltrue([
      yamldecode(helm_release.mimir[0].values[0]).serviceAccount.name == "mimir",
      yamldecode(helm_release.loki[0].values[0]).serviceAccount.name == "loki",
      yamldecode(helm_release.tempo[0].values[0]).serviceAccount.name == "tempo",
      yamldecode(helm_release.grafana[0].values[0]).serviceAccount.name == "grafana",
    ])
    error_message = "service accounts are exactly those core-platform binds with Pod Identity (monitoring/mimir, loki, tempo, grafana)"
  }
}

run "gpu_metrics_scraped" {
  command = plan

  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "nvidia-dcgm-exporter")
    error_message = "Alloy scrapes the GPU operator's DCGM exporter pods by label, not only annotated pods"
  }
}

run "bucket_from_observability_state" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.common.storage.s3.bucket_name == "research-shared-euw1-observability-111111111111"
    error_message = "Mimir writes to the group's observability bucket"
  }
  assert {
    condition     = yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.no_auth_tenant == "research-sandbox-euw1-1-eks" && yamldecode(helm_release.mimir[0].values[0]).mimir.structuredConfig.blocks_storage.storage_prefix == "mimir"
    error_message = "Mimir's objects land under mimir/<cluster name>/ (prefix mimir, tenant = cluster name)"
  }
  assert {
    condition     = yamldecode(helm_release.loki[0].values[0]).loki.storage.object_store.storage_prefix == "loki-research-sandbox-euw1-1-eks"
    error_message = "Loki's objects land under loki-<cluster name>/"
  }
  assert {
    condition     = yamldecode(helm_release.tempo[0].values[0]).tempo.storage.trace.s3.prefix == "tempo/research-sandbox-euw1-1-eks"
    error_message = "Tempo's objects land under tempo/<cluster name>/"
  }
}

run "missing_observability_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.observability
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
    condition     = length(helm_release.mimir) + length(helm_release.loki) + length(helm_release.tempo) + length(helm_release.alloy) + length(helm_release.grafana) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
