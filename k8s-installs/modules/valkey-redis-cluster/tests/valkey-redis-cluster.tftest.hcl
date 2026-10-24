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
  config_file = "tests/fixtures/valkey-redis-cluster.cache.yaml"
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
    condition = alltrue([
      helm_release.cluster[0].name == "valkey-cache",
      yamldecode(helm_release.cluster[0].values[0]).shards == 1,
      yamldecode(helm_release.cluster[0].values[0]).replicas == 0,
      yamldecode(helm_release.cluster[0].values[0]).storageSize == "5Gi",
    ])
    error_message = "one Valkey cluster per unit, named after the instance, platform-sized"
  }
  assert {
    condition     = module.credentials.secret_names["default"] == "acme/vision-sandbox/redis/in-cluster/cache" && yamldecode(helm_release.cluster[0].values[0]).defaultSmSecretName == "acme/vision-sandbox/redis/in-cluster/cache"
    error_message = "the default user's password publishes under <organisation>/<env_id>/redis/in-cluster/<instance>"
  }
}

run "two_instances_do_not_collide" {
  command = plan

  variables {
    config_file = "tests/fixtures/valkey-redis-cluster.sessions.yaml"
  }

  assert {
    condition     = helm_release.cluster[0].name == "valkey-sessions" && module.credentials.secret_names["user-app"] == "acme/vision-sandbox/redis/in-cluster/sessions/app"
    error_message = "a second instance gets its own cluster and secret paths, users included"
  }
  assert {
    condition     = yamldecode(helm_release.cluster[0].values[0]).users[0].permissions == "+@read ~app:*"
    error_message = "per-user ACLs pass through"
  }
}

run "missing_instance_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/valkey-redis-cluster.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/valkey-redis-cluster.off.yaml"
  }

  assert {
    condition     = length(helm_release.cluster) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
