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
    condition     = helm_release.base[0].version == "1.30.1" && helm_release.istiod[0].version == "1.30.1" && helm_release.istiod[0].namespace == "istio-system"
    error_message = "istio base and istiod install the pinned chart into istio-system"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.extras[0].values[0]).certs.internalZoneName == "internal.sandbox.research.example.com",
      yamldecode(helm_release.extras[0].values[0]).gateways.internal.enabled == true,
      yamldecode(helm_release.extras[0].values[0]).gateways.external.enabled == false,
    ])
    error_message = "an internal gateway on the cluster's internal zone by default; no external gateway"
  }
  assert {
    condition     = yamldecode(helm_release.extras[0].values[0]).gateways.internal.serviceAnnotations["service.beta.kubernetes.io/aws-load-balancer-scheme"] == "internal"
    error_message = "the internal gateway gets an internal NLB from the load balancer controller"
  }
  assert {
    condition     = output.gateways.internal.name == "istio-internal" && output.gateways.internal.namespace == "istio-system" && output.gateways.internal.domain == "internal.sandbox.research.example.com"
    error_message = "the internal gateway is published for vllm and other routes"
  }
}

run "gateway_and_inference_crds" {
  command = plan

  assert {
    condition     = helm_release.crds[0].name == "gateway-api-crds" && helm_release.base[0].name == "istio-base"
    error_message = "the Gateway API CRDs are their own release, before istio"
  }
  assert {
    condition = alltrue([
      fileexists("${path.module}/manifests/gateway-crds/templates/gateway-api-standard-v1.5.1.yaml"),
      fileexists("${path.module}/manifests/gateway-crds/templates/inference-extension-v1.6.2.yaml"),
    ])
    error_message = "Gateway API (standard) and Inference Extension (InferencePool) CRDs ship with istio"
  }
}

run "external_gateway_on_request" {
  command = plan

  variables {
    config_file = "tests/fixtures/external.yaml"
  }

  assert {
    condition     = yamldecode(helm_release.extras[0].values[0]).gateways.external.serviceAnnotations["service.beta.kubernetes.io/aws-load-balancer-scheme"] == "internet-facing" && output.gateways.external.domain == "sandbox.research.example.com"
    error_message = "the external gateway, when asked for, gets an internet-facing NLB on the public zone"
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
    condition     = length(helm_release.crds) + length(helm_release.base) + length(helm_release.istiod) + length(helm_release.extras) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}

run "internal_nlb_preserves_client_ip" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.extras[0].values[0]).gateways.internal.serviceAnnotations["service.beta.kubernetes.io/aws-load-balancer-target-group-attributes"] == "preserve_client_ip.enabled=true"
    error_message = "the internal gateway sees callers' own addresses (IP targets don't preserve them by default): model access is by caller CIDR"
  }
}

run "gateway_metrics_carry_consumer" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.extras[0].values[0]).telemetry.consumerTags == true
    error_message = "the gateways' request metrics carry consumer (x-phoenix-consumer) and request_host, for the Model serving dashboard"
  }
}
