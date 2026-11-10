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

# Only global_receiver reads it: the internal gateway its HTTPRoute attaches to.
override_data {
  target = data.terraform_remote_state.istio
  values = {
    outputs = {
      gateways = {
        internal = { name = "istio-internal", namespace = "istio-system", domain = "internal.sandbox.research.example.com" }
        external = null
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

run "model_serving_dashboards" {
  command = plan

  assert {
    condition = alltrue([
      for uid in ["phoenix-model-serving", "llm-d-vllm-overview", "llm-d-inference-gateway", "llm-d-performance-kv-cache", "llm-d-failure-saturation"] :
      contains([for d in values(yamldecode(helm_release.grafana[0].values[1]).dashboards["model-serving"]) : jsondecode(d.json).uid], uid)
    ])
    error_message = "the Model serving dashboard and llm-d's published dashboards are provisioned"
  }
  assert {
    condition = alltrue([
      for d in values(yamldecode(helm_release.grafana[0].values[1]).dashboards["model-serving"]) :
      anytrue([for v in try(jsondecode(d.json).templating.list, []) : v.type == "datasource" && v.query == "prometheus"]) || jsondecode(d.json).uid == "phoenix-model-serving"
    ])
    error_message = "vendored dashboards choose their Prometheus data source by variable (the default, Mimir)"
  }
  assert {
    condition = toset([for r in yamldecode(helm_release.grafana[0].values[1]).alerting["model-serving.yaml"].groups[0].rules : r.title]) == toset([
      "ModelStartSlow", "AcceleratorIdle", "ModelPendingCapacity",
    ])
    error_message = "the three anti-goal alerts: slow start, idle accelerators, pending for capacity"
  }
  assert {
    condition     = helm_release.kube_state_metrics[0].version == "8.6.0"
    error_message = "kube-state-metrics (pod start and Pending reasons), pinned"
  }
  assert {
    condition     = strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "karpenter;http-metrics")
    error_message = "Alloy scrapes Karpenter's metrics"
  }
}

# Before model_serving_off: a run that errors makes terraform test skip the rest.
run "cost_dashboard_provisioned" {
  command = plan

  assert {
    condition     = try(jsondecode(yamldecode(helm_release.grafana[0].values[length(helm_release.grafana[0].values) - 1]).dashboards["cost"]["cost"].json).uid, null) == "phoenix-cost"
    error_message = "the Cost dashboard is provisioned, last so it overrides nothing"
  }
  assert {
    condition = toset([
      for p in try(jsondecode(yamldecode(helm_release.grafana[0].values[length(helm_release.grafana[0].values) - 1]).dashboards["cost"]["cost"].json).panels, []) : p.title
    ]) == toset(["Cost per namespace", "Cost per model", "Cost per GPU type"])
    error_message = "cost per namespace, per model and per GPU type"
  }
  assert {
    condition = alltrue([
      for p in try(jsondecode(yamldecode(helm_release.grafana[0].values[length(helm_release.grafana[0].values) - 1]).dashboards["cost"]["cost"].json).panels, [{ datasource = { uid = "none" } }]) : p.datasource.uid == "mimir"
    ])
    error_message = "every Cost panel queries Mimir"
  }
}

run "model_serving_off" {
  command = plan

  variables {
    config_file = "tests/fixtures/no-model-serving.yaml"
  }

  assert {
    condition = alltrue([
      length(helm_release.grafana[0].values) == 2,
      !contains(keys(try(yamldecode(helm_release.grafana[0].values[1]).dashboards, {})), "model-serving"),
      length(helm_release.kube_state_metrics) == 0,
    ])
    error_message = "spec.model_serving: false provisions no model-serving dashboards, alerts or kube-state-metrics"
  }
  assert {
    condition     = contains(keys(try(yamldecode(helm_release.grafana[0].values[1]).dashboards, {})), "cost")
    error_message = "the Cost dashboard does not depend on model serving"
  }
}

run "global_write_off_by_default" {
  command = plan

  assert {
    condition = alltrue([
      !strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "prometheus.remote_write \"global\""),
      length(helm_release.global_metrics) == 0,
    ])
    error_message = "without spec.global_metrics a cluster's metrics stay in its own Mimir"
  }
}

run "global_write_allowlist" {
  command = plan

  variables {
    config_file = "tests/fixtures/global-send.yaml"
  }

  assert {
    condition = alltrue([
      strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "url = \"https://metrics-1.internal.prod.platform.example.com/api/v1/push\""),
      strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "regex         = \"${join("|", local.global_allowlist)}\""),
      strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "forward_to = [prometheus.remote_write.mimir.receiver, prometheus.remote_write.global.receiver]"),
      strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "cloud   = \"aws\""),
      strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "env_id  = \"research-sandbox\""),
      strcontains(yamldecode(helm_release.alloy[0].values[0]).alloy.configMap.content, "tier    = \"sandbox\""),
    ])
    error_message = "a sending cluster forwards only the allowlisted series to the management cluster over HTTPS, labelled with its cluster, environment, tier and cloud"
  }
  assert {
    condition = toset(local.global_allowlist) == toset([
      "DCGM_FI_DEV_GPU_UTIL", "llm_d_epp_request_running", "istio_requests_total", "karpenter_nodes_allocatable",
      "node_total_hourly_cost", "node_cpu_hourly_cost", "node_ram_hourly_cost", "node_gpu_hourly_cost",
      "container_cpu_allocation", "container_memory_allocation_bytes", "container_gpu_allocation",
    ])
    error_message = "the allowlist: GPU use, inference load, gateway traffic, node pools and OpenCost's cost series"
  }
  assert {
    condition = alltrue([
      try(yamldecode(helm_release.global_metrics[0].values[0]).send.secretName, "") == "acme/research-sandbox/global-metrics",
      try(yamldecode(helm_release.global_metrics[0].values[0]).receive, "missing") == null,
      contains([for e in try(yamldecode(helm_release.alloy[0].values[1]).alloy.extraEnv, []) : e.valueFrom.secretKeyRef.key if e.name == "GLOBAL_METRICS_PASSWORD"], "password"),
    ])
    error_message = "the write credential comes from the environment's own secrets prefix (ADR-0007) into Alloy's environment, never into the config"
  }
}

run "global_write_requires_https" {
  command = plan

  variables {
    config_file = "tests/fixtures/global-send-http.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "receiver_is_internal_only" {
  command = plan

  variables {
    config_file = "tests/fixtures/global-receiver.yaml"
  }

  assert {
    condition = alltrue([
      try(yamldecode(helm_release.global_metrics[0].values[0]).receive.gateway, null) == { name = "istio-internal", namespace = "istio-system" },
      try(yamldecode(helm_release.global_metrics[0].values[0]).receive.hostname, "") == "metrics-1.internal.sandbox.research.example.com",
    ])
    error_message = "the receiver is reachable only on the internal gateway, by a name its wildcard certificate covers (TLS)"
  }
}

run "receiver_requires_auth" {
  command = plan

  variables {
    config_file = "tests/fixtures/global-receiver.yaml"
  }

  assert {
    condition = alltrue([
      try(yamldecode(helm_release.global_metrics[0].values[0]).receive.secretName, "") == "acme/research-sandbox/global-metrics",
      try(yamldecode(helm_release.global_metrics[0].values[0]).receive.upstream, "") == "http://mimir-gateway.monitoring.svc",
    ])
    error_message = "writes reach Mimir only through the authenticating proxy, its password file from the environment's secrets prefix"
  }
}

run "global_cost_dashboard" {
  command = plan

  variables {
    config_file = "tests/fixtures/global-receiver.yaml"
  }

  assert {
    condition = alltrue([
      try(jsondecode(yamldecode(helm_release.grafana[0].values[length(helm_release.grafana[0].values) - 1]).dashboards["global"]["global-cost"].json).uid, "") == "phoenix-global-cost",
      toset([for p in try(jsondecode(yamldecode(helm_release.grafana[0].values[length(helm_release.grafana[0].values) - 1]).dashboards["global"]["global-cost"].json).panels, []) : p.title]) == toset([
        "Cost per cloud", "Cost per cluster", "Cost per namespace", "Cost per model", "Cost per GPU type",
      ]),
    ])
    error_message = "the management cluster's Grafana shows cost across clouds and clusters"
  }
}

run "receiver_needs_internal_gateway" {
  command = plan

  variables {
    config_file = "tests/fixtures/global-receiver.yaml"
  }

  override_data {
    target = data.terraform_remote_state.istio
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}
