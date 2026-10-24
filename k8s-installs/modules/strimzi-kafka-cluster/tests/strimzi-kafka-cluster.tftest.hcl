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
  config_file = "tests/fixtures/strimzi-kafka-cluster.events.yaml"
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
      helm_release.cluster[0].name == "kafka-events",
      yamldecode(helm_release.cluster[0].values[0]).topology == "dual-role",
      yamldecode(helm_release.cluster[0].values[0]).instances == 1,
    ])
    error_message = "one Kafka cluster per unit, named after the instance; nonprod preset by default"
  }
  assert {
    condition     = module.credentials.secret_names["user-app"] == "acme/vision-sandbox/kafka/in-cluster/events/app"
    error_message = "user passwords publish under <organisation>/<env_id>/kafka/in-cluster/<instance>/<user>"
  }
  assert {
    condition     = yamldecode(helm_release.users[0].values[0]).users[0].name == "kafka-events-app" && yamldecode(helm_release.topics[0].values[0]).topics[0].resourceName == "kafka-events-orders"
    error_message = "KafkaUser and KafkaTopic objects are prefixed with the cluster name"
  }
}

run "two_instances_do_not_collide" {
  command = plan

  variables {
    config_file = "tests/fixtures/strimzi-kafka-cluster.audit.yaml"
  }

  assert {
    condition = alltrue([
      helm_release.cluster[0].name == "kafka-audit",
      yamldecode(helm_release.users[0].values[0]).users[0].name == "kafka-audit-app",
      yamldecode(helm_release.topics[0].values[0]).topics[0].resourceName == "kafka-audit-orders",
      yamldecode(helm_release.topics[0].values[0]).topics[0].name == "orders",
      module.credentials.secret_names["user-app"] == "acme/vision-sandbox/kafka/in-cluster/audit/app",
    ])
    error_message = "same topic and user names in a second cluster get distinct objects and secrets; the topic keeps its real name"
  }
}

run "missing_instance_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/strimzi-kafka-cluster.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/strimzi-kafka-cluster.off.yaml"
  }

  assert {
    condition     = length(helm_release.cluster) + length(helm_release.topics) + length(helm_release.users) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
