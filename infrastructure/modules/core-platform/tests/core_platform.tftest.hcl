# The upstream EKS module validates ARNs and policy JSON, so the mock returns
# well-formed values for the data sources it reads.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:sts::111111111111:assumed-role/Terraform-Role/github"
    }
  }
  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::111111111111:role/Terraform-Role"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }
}

variables {
  config_file = "tests/fixtures/core-platform.yaml"
}

override_data {
  target = module.context.data.terraform_remote_state.core_network[0]
  values = {
    outputs = {
      default_vpc_name = "vpc-1"
      networks = {
        "vpc-1" = {
          vpc_id              = "vpc-123"
          private_subnet_ids  = ["subnet-d1", "subnet-d2", "subnet-d3", "subnet-p1", "subnet-p2", "subnet-p3"]
          platform_subnet_ids = ["subnet-p1", "subnet-p2", "subnet-p3"]
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.observability[0]
  values = {
    outputs = {
      writer_role_arns = {
        mimir    = "arn:aws:iam::111111111111:role/vision-shared-euw1-mimir"
        loki     = "arn:aws:iam::111111111111:role/vision-shared-euw1-loki"
        tempo    = "arn:aws:iam::111111111111:role/vision-shared-euw1-tempo"
        langfuse = "arn:aws:iam::111111111111:role/vision-shared-euw1-langfuse"
      }
      grafana_cloudwatch_role_arn = "arn:aws:iam::111111111111:role/vision-shared-euw1-grafana-cloudwatch"
    }
  }
}

run "cluster_in_selected_vpc" {
  command = plan

  assert {
    condition     = output.clusters["1"].vpc_id == "vpc-123"
    error_message = "cluster 1 sits in the default VPC from core-network's state"
  }
  assert {
    condition     = output.clusters["1"].cluster_name == "vision-sandbox-euw1-1-eks"
    error_message = "cluster name is <name_prefix>-<key>-eks"
  }
  assert {
    condition     = contains(keys(output.clusters["1"]), "cluster_certificate_authority_data")
    error_message = "clusters carries the CA, so k8s-installs can connect without an EKS API call"
  }
  assert {
    condition     = toset(output.clusters["1"].node_subnet_ids) == toset(["subnet-p1", "subnet-p2", "subnet-p3"])
    error_message = "clusters carries the node subnets, so Karpenter's node classes select them by ID"
  }
}

run "gpu_node_group_passthrough" {
  command = plan

  assert {
    condition = anytrue([
      for t in module.eks["1"].eks_managed_node_groups["gpu-1"].node_group_taints : t.key == "nvidia.com/gpu" && t.effect == "NO_SCHEDULE"
    ])
    error_message = "the GPU node group carries the nvidia.com/gpu NoSchedule taint from the YAML"
  }
}

run "observability_associations" {
  command = plan

  assert {
    condition     = toset(keys(aws_eks_pod_identity_association.observability)) == toset(["1/mimir", "1/loki", "1/tempo", "1/langfuse", "1/grafana"])
    error_message = "one association per cluster and writer, plus Grafana's CloudWatch role"
  }
  assert {
    condition     = aws_eks_pod_identity_association.observability["1/mimir"].namespace == "monitoring" && aws_eks_pod_identity_association.observability["1/mimir"].service_account == "mimir"
    error_message = "mimir binds to monitoring/mimir by default"
  }
  assert {
    condition     = aws_eks_pod_identity_association.observability["1/langfuse"].namespace == "langfuse" && aws_eks_pod_identity_association.observability["1/langfuse"].service_account == "langfuse"
    error_message = "langfuse binds to langfuse/langfuse by default"
  }
  assert {
    condition     = aws_eks_pod_identity_association.observability["1/grafana"].role_arn == "arn:aws:iam::111111111111:role/vision-shared-euw1-grafana-cloudwatch"
    error_message = "grafana binds to the CloudWatch read role"
  }
}

run "observability_disabled" {
  command = plan

  variables {
    config_file = "tests/fixtures/no_observability.yaml"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.observability) == 0
    error_message = "no observability associations when spec.observability.enabled is false"
  }
}

run "network_missing_rejected" {
  command = plan

  override_data {
    target = module.context.data.terraform_remote_state.core_network[0]
    values = {
      outputs = {}
    }
  }

  expect_failures = [terraform_data.validation]
}

run "shared_addon_pin_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/shared_addon_pin.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "personal_environment_names_fit" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  override_data {
    target = data.terraform_remote_state.observability[0]
    values = {
      outputs = {
        writer_role_arns = {
          mimir    = "arn:aws:iam::111111111111:role/vision-shared-euw1-mimir"
          loki     = "arn:aws:iam::111111111111:role/vision-shared-euw1-loki"
          tempo    = "arn:aws:iam::111111111111:role/vision-shared-euw1-tempo"
          langfuse = "arn:aws:iam::111111111111:role/vision-shared-euw1-langfuse"
        }
        grafana_cloudwatch_role_arn = "arn:aws:iam::111111111111:role/vision-shared-euw1-grafana-cloudwatch"
      }
    }
  }

  assert {
    condition     = output.clusters["1"].cluster_name == "vision-sandbox-jdoe-euw1-1-eks"
    error_message = "a personal environment's cluster plans with its full name"
  }
}
