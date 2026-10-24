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
  config_file = "tests/fixtures/karpenter-nodepool.l4.yaml"
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

run "gpu_pool_from_instance" {
  command = plan

  assert {
    condition     = helm_release.this[0].name == "karpenter-nodepool-l4" && helm_release.this[0].namespace == "karpenter"
    error_message = "one release per GPU type, named after the instance"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.this[0].values[0]).name == "gpu-l4",
      yamldecode(helm_release.this[0].values[0]).instanceFamilies[0] == "g6",
      yamldecode(helm_release.this[0].values[0]).gpuCountMax == 1,
      yamldecode(helm_release.this[0].values[0]).nodeClass.role == "vision-sandbox-euw1-1-karpenter-node",
    ])
    error_message = "NodePool/EC2NodeClass gpu-<instance> from spec (families, max GPUs) and core-platform's node role"
  }
}

run "two_gpu_types_do_not_collide" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.a10g.yaml"
  }

  assert {
    condition     = helm_release.this[0].name == "karpenter-nodepool-a10g" && yamldecode(helm_release.this[0].values[0]).name == "gpu-a10g"
    error_message = "a second GPU type gets its own release and pool"
  }
}

run "families_required" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.bad.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.disabled.yaml"
  }

  assert {
    condition     = length(helm_release.this) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
