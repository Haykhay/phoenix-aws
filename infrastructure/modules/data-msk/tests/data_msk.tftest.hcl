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
  config_file = "tests/fixtures/msk.yaml"
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
    condition     = aws_security_group.msk["core"].vpc_id == "vpc-123"
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

run "secret_path_uses_organisation" {
  command = plan

  assert {
    condition     = alltrue([for name in values(module.scram_credentials.secret_names) : startswith(name, "AmazonMSK_acme_")])
    error_message = "MSK SCRAM secrets are named AmazonMSK_<organisation>_..."
  }
}
