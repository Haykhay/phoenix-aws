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
  config_file = "tests/fixtures/cloudnative-pg-cluster.app.yaml"
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
    condition     = helm_release.cluster[0].name == "cnpg-app" && helm_release.cluster[0].namespace == "cnpg-system"
    error_message = "one Postgres cluster per unit, named after the instance"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.cluster[0].values[0]).instances == 1,
      yamldecode(helm_release.cluster[0].values[0]).storageSize == "10Gi",
      length(yamldecode(helm_release.cluster[0].values[0]).databases) == 1,
      yamldecode(helm_release.cluster[0].values[0]).databases[0].name == "app",
    ])
    error_message = "platform defaults: 1 instance, 10Gi, one database named after the instance"
  }
  assert {
    condition = alltrue([
      module.credentials.secret_names["superuser"] == "acme/research-sandbox/postgres/in-cluster/app",
      module.credentials.secret_names["db-app"] == "acme/research-sandbox/postgres/in-cluster/app/app",
      yamldecode(helm_release.cluster[0].values[0]).databases[0].smSecretName == "acme/research-sandbox/postgres/in-cluster/app/app",
    ])
    error_message = "credentials publish under <organisation>/<env_id>/postgres/in-cluster/<instance>[/<db>], inside external-secrets' scope"
  }
}

run "two_instances_do_not_collide" {
  command = plan

  variables {
    config_file = "tests/fixtures/cloudnative-pg-cluster.analytics.yaml"
  }

  assert {
    condition     = helm_release.cluster[0].name == "cnpg-analytics" && module.credentials.secret_names["superuser"] == "acme/research-sandbox/postgres/in-cluster/analytics"
    error_message = "a second instance gets its own cluster and secret paths"
  }
  assert {
    condition     = module.credentials.secret_names["db-reports"] == "acme/research-sandbox/postgres/in-cluster/analytics/reports" && yamldecode(helm_release.cluster[0].values[0]).databases[1].role == "reporter"
    error_message = "several databases per cluster, each with its own role and secret"
  }
}

run "missing_instance_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/cloudnative-pg-cluster.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/cloudnative-pg-cluster.off.yaml"
  }

  assert {
    condition     = length(helm_release.cluster) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
