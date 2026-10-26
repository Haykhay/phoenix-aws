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
          cluster_security_group_id          = "sg-cluster-1"
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
        "2" = {
          cluster_name                       = "research-sandbox-euw1-2-eks"
          cluster_endpoint                   = "https://DEF.gr7.eu-west-1.eks.amazonaws.com"
          cluster_certificate_authority_data = "Q0EtREFUQQ=="
          node_security_group_id             = "sg-456"
          cluster_security_group_id          = "sg-cluster-2"
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

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.this[0].version == "7.9.1" && helm_release.this[0].namespace == "argocd"
    error_message = "Argo CD installs the pinned chart into argocd"
  }
  assert {
    condition     = !strcontains(file("${path.module}/manifests/values.yaml.tpl"), "extraHosts") && strcontains(file("${path.module}/manifests/values.yaml.tpl"), "ingress:\n    enabled: false")
    error_message = "no custom SSH host keys (the chart knows github.com) and no ingress (exposed through istio)"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.route[0].values[0]).hostname == "argocd-1.internal.sandbox.research.example.com",
      yamldecode(helm_release.route[0].values[0]).gateway.name == "istio-internal",
      yamldecode(helm_release.route[0].values[0]).service.name == "argocd-server",
    ])
    error_message = "the UI is an HTTPRoute on istio's internal gateway, per cluster"
  }
  assert {
    condition     = yamldecode(helm_release.bootstrap[0].values[0]).repoUrl == "git@github.com:acme/phoenix-apps.git" && yamldecode(helm_release.bootstrap[0].values[0]).valuesFile == "clusters/research-sandbox-1.yaml"
    error_message = "the bootstrap app watches spec.repo_url with a per-cluster values file"
  }
  assert {
    condition     = aws_secretsmanager_secret.admin[0].name == "acme/research-sandbox/argo-cd/1/admin" && aws_secretsmanager_secret.repo_ssh[0].name == "acme/research-sandbox/argo-cd/1/repo-ssh-key"
    error_message = "secrets live per cluster under <organisation>/<env_id>/argo-cd/<cluster>/"
  }
}

run "ecr_pull_through_scoped" {
  command = plan

  assert {
    condition     = length(local.ecr_pull_arns) == 1 && local.ecr_pull_arns[0] == "arn:aws:ecr:eu-west-1:111111111111:repository/artifactory/*"
    error_message = "OCI charts come only from the group account's pull-through cache"
  }
  assert {
    condition     = yamldecode(helm_release.ecr_credentials[0].values[0]).accountIds[0] == "111111111111" && length(yamldecode(helm_release.ecr_credentials[0].values[0]).accountIds) == 1
    error_message = "registry credentials for the group account only (no shared account)"
  }
  assert {
    condition     = !strcontains(file("${path.module}/manifests/ecr-credentials/templates/ecr-credentials.yaml"), "registryId")
    error_message = "ECRAuthorizationToken (external-secrets 2.6.0) has no registryId field; the token covers every registry the role can reach"
  }
}

run "repo_url_required" {
  command = plan

  variables {
    config_file = "tests/fixtures/no_repo.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "personal_env_names_fit" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  assert {
    condition     = length(aws_iam_role.repo_server[0].name) <= 64
    error_message = "a personal environment's role name fits IAM's 64 characters"
  }
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.this) + length(aws_iam_role.repo_server) + length(aws_secretsmanager_secret.admin) == 0
    error_message = "spec.enabled: false creates nothing"
  }
}
