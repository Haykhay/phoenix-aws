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
    condition     = helm_release.this[0].version == "3.4.0" && helm_release.this[0].namespace == "kube-system"
    error_message = "the controller installs the pinned chart into kube-system"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.this[0].values[0]).clusterName == "vision-sandbox-euw1-1-eks",
      yamldecode(helm_release.this[0].values[0]).vpcId == "vpc-123",
      yamldecode(helm_release.this[0].values[0]).region == "eu-west-1",
      yamldecode(helm_release.this[0].values[0]).defaultTags.Project == "Phoenix",
      yamldecode(helm_release.this[0].values[0]).defaultTags.Cluster == "1",
    ])
    error_message = "cluster, VPC (no IMDS lookup) and region are set; load balancers carry the unit's tags"
  }
  assert {
    condition     = aws_eks_pod_identity_association.this[0].service_account == "aws-load-balancer-controller" && aws_iam_role.this[0].name == "vision-sandbox-euw1-1-aws-load-balancer-controller"
    error_message = "Pod Identity binds kube-system/aws-load-balancer-controller to <name_prefix>-aws-load-balancer-controller"
  }
}

run "personal_env_names_fit" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  assert {
    condition     = length(aws_iam_role.this[0].name) <= 64 && length(aws_iam_policy.this[0].name) <= 128
    error_message = "a personal environment's role (64) and policy (128) names fit IAM's limits"
  }
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
