mock_provider "aws" {}

variables {
  state   = { bucket = "acme-tfstate-111111111111", region = "eu-west-1" }
  env_id  = "vision-sandbox"
  region  = "eu-west-1"
  cluster = "1"
}

override_data {
  target = data.terraform_remote_state.core_platform
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
          node_subnet_ids                    = ["subnet-p1", "subnet-p2"]
          karpenter                          = null
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.dns
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

run "finds_cluster" {
  command = plan

  assert {
    condition     = output.cluster_name == "vision-sandbox-euw1-1-eks"
    error_message = "cluster 1's name comes from core-platform's clusters output"
  }
  assert {
    condition     = output.vpc_id == "vpc-123" && output.cluster_ca_data == "Q0EtREFUQQ=="
    error_message = "VPC and CA come from the same cluster entry"
  }
  assert {
    condition     = length(output.node_subnet_ids) == 2 && output.node_subnet_ids[0] == "subnet-p1"
    error_message = "node subnets come from the same cluster entry"
  }
  assert {
    condition     = output.cluster_security_group_id == "sg-cluster-1"
    error_message = "the EKS cluster security group, for components that open the API to other clusters"
  }
  assert {
    condition     = output.dns.public_zone_name == "sandbox.vision.example.com"
    error_message = "the cluster's DNS zone is zone-1 by default"
  }
  assert {
    condition     = keys(output.dns_zones) == ["zone-1"]
    error_message = "every zone of the environment is exposed, for components that may span zones"
  }
}

run "unknown_cluster_rejected" {
  command = plan

  variables {
    cluster = "9"
  }

  expect_failures = [terraform_data.validation]
}

run "missing_core_platform_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.core_platform
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "dns_optional" {
  command = plan

  override_data {
    target = data.terraform_remote_state.dns
    values = { outputs = {} }
  }

  assert {
    condition     = output.dns == null
    error_message = "an environment without a dns unit gives dns = null, not an error"
  }
}
