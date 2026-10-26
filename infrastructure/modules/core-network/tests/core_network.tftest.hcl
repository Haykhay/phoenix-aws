mock_provider "aws" {}

mock_provider "aws" {
  alias = "network"
}

mock_provider "aws" {
  alias = "network_dublin"
}

variables {
  config_file = "tests/fixtures/pool.yaml"
}

run "pool_vpc_plans" {
  command = plan

  assert {
    condition     = length(output.vpc_names) == 1 && output.vpc_names[0] == "vpc-1"
    error_message = "one VPC, keyed vpc-1"
  }
  assert {
    condition     = output.name_prefix == "research-sandbox-euw1"
    error_message = "account/region resources are named from the context prefix"
  }
  assert {
    condition     = module.vpc["vpc-1"].name == "research-sandbox-euw1-vpc-1"
    error_message = "VPC name is <name_prefix>-<vpc key>"
  }
  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.this["vpc-1"].netmask_length == 18
    error_message = "pool VPCs claim a /18 from IPAM by default"
  }
}

run "literal_cidr_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/literal_cidr.yaml"
  }

  expect_failures = [aws_vpc_ipam_pool_cidr_allocation.this]
}

run "tgw_requires_network_provider" {
  command = plan

  variables {
    config_file = "tests/fixtures/tgw_without_provider.yaml"
  }

  expect_failures = [aws_ec2_transit_gateway_vpc_attachment.this]
}
