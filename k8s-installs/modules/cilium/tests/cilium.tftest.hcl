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

override_data {
  target = data.aws_vpc.cluster
  values = {
    cidr_block = "10.64.0.0/20"
  }
}

run "chaining_values" {
  command = plan

  assert {
    condition     = helm_release.this[0].chart == "cilium" && helm_release.this[0].version == "1.20.2" && helm_release.this[0].namespace == "kube-system"
    error_message = "the pinned cilium chart, in kube-system"
  }
  assert {
    condition = (
      yamldecode(helm_release.this[0].values[0]).cni.chainingMode == "aws-cni" &&
      yamldecode(helm_release.this[0].values[0]).cni.exclusive == false &&
      yamldecode(helm_release.this[0].values[0]).enableIPv4Masquerade == false &&
      yamldecode(helm_release.this[0].values[0]).routingMode == "native" &&
      yamldecode(helm_release.this[0].values[0]).kubeProxyReplacement == false
    )
    error_message = "chaining with the VPC CNI: native routing, no masquerade, kube-proxy kept"
  }
}

run "default_policy_destinations" {
  command = plan

  assert {
    condition     = toset(yamldecode(helm_release.policy[0].values[0]).allowCidrs) == toset(["10.64.0.0/20", "10.128.0.0/10", "169.254.170.23/32", "169.254.169.254/32"])
    error_message = "own VPC, the shared segment (tooling), Pod Identity, instance metadata"
  }
  assert {
    condition     = toset(yamldecode(helm_release.policy[0].values[0]).internetExcept) == toset(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])
    error_message = "internet is everything outside RFC 1918"
  }
  assert {
    condition     = length(yamldecode(helm_release.policy[0].values[0]).allowFqdns) == 0
    error_message = "no FQDNs opened by default"
  }
}

run "egress_allow_extends_policy" {
  command = plan

  variables {
    config_file = "tests/fixtures/egress_allow.yaml"
  }

  assert {
    condition     = contains(yamldecode(helm_release.policy[0].values[0]).allowCidrs, "192.168.10.0/24") && contains(yamldecode(helm_release.policy[0].values[0]).allowFqdns, "*.corp.local")
    error_message = "platform-managed egress_allow opens CIDRs and FQDNs"
  }
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.this) == 0 && length(helm_release.policy) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}

run "onprem_denied_even_outside_rfc1918" {
  command = plan

  variables {
    config_file = "tests/fixtures/onprem_public.yaml"
  }

  assert {
    condition     = contains(yamldecode(helm_release.policy[0].values[0]).internetExcept, "100.64.0.0/16")
    error_message = "on-prem ranges are never 'internet', whatever their addresses"
  }
}
