# The upstream modules validate ARNs and policy JSON, so the mock returns
# well-formed values for the data sources they read.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:sts::111111111111:assumed-role/Terraform-Role/github"
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
}

mock_provider "random" {}

variables {
  config_file = "tests/fixtures/rds.yaml"
}

override_data {
  target = module.context.data.terraform_remote_state.core_network[0]
  values = {
    outputs = {
      default_vpc_name = "vpc-1"
      networks = {
        "vpc-1" = {
          vpc_id              = "vpc-123"
          data_subnet_ids     = ["subnet-d1", "subnet-d2", "subnet-d3"]
          platform_subnet_ids = ["subnet-p1", "subnet-p2", "subnet-p3"]
          private_subnet_ids  = ["subnet-d1", "subnet-d2", "subnet-d3", "subnet-p1", "subnet-p2", "subnet-p3"]
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.core_platform[0]
  values = {
    outputs = {
      clusters = {
        "1" = { node_security_group_id = "sg-node-1" }
      }
    }
  }
}

run "plans_in_selected_vpc" {
  command = plan

  assert {
    condition     = aws_security_group.rds["core"].vpc_id == "vpc-123"
    error_message = "the security group sits in the default VPC from core-network's state"
  }
}

run "eks_binding_required" {
  command = plan

  override_data {
    target = data.terraform_remote_state.core_platform[0]
    values = {
      outputs = {
        clusters = {
          "1" = { node_security_group_id = "sg-node-1" }
          "2" = { node_security_group_id = "sg-node-2" }
        }
      }
    }
  }

  expect_failures = [terraform_data.validation]
}

run "eks_binding_named" {
  command = plan

  variables {
    config_file = "tests/fixtures/rds_bound.yaml"
  }

  override_data {
    target = data.terraform_remote_state.core_platform[0]
    values = {
      outputs = {
        clusters = {
          "1" = { node_security_group_id = "sg-node-1" }
          "2" = { node_security_group_id = "sg-node-2" }
        }
      }
    }
  }

  assert {
    condition     = contains(keys(aws_vpc_security_group_ingress_rule.security_group), "core/sg-node-1")
    error_message = "the named cluster's node security group gets ingress"
  }
  assert {
    condition     = !contains(keys(aws_vpc_security_group_ingress_rule.security_group), "core/sg-node-2")
    error_message = "an unnamed cluster's node security group gets none"
  }
}

run "minimal_instance_plans" {
  command = plan

  variables {
    config_file = "tests/fixtures/minimal.yaml"
  }

  assert {
    condition     = aws_security_group.rds["core"].vpc_id == "vpc-123"
    error_message = "an instance with only engine, version, family, class and storage plans; the rest has defaults"
  }
}
