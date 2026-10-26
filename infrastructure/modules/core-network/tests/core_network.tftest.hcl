mock_provider "aws" {}

mock_provider "aws" {
  alias = "network"
}

variables {
  config_file = "tests/fixtures/pool.yaml"
}

# eu-west-1's region unit, in the networking account.
override_data {
  target = data.terraform_remote_state.region[0]
  values = {
    outputs = {
      transit_gateway_id = "tgw-0abc"
      route_table_ids    = { production = "tgw-rtb-prod", "non-production" = "tgw-rtb-nonprod", shared = "tgw-rtb-shared" }
      pool_ids           = { production = "ipam-pool-prod", "non-production" = "ipam-pool-nonprod", shared = "ipam-pool-shared" }
      egress_mode        = "central"
    }
  }
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
}

run "sandbox_is_non_production" {
  command = plan

  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.this["vpc-1"].ipam_pool_id == "ipam-pool-nonprod" && aws_vpc_ipam_pool_cidr_allocation.this["vpc-1"].netmask_length == 20
    error_message = "sandbox: the region's non-production pool, /20"
  }
  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.this["vpc-1"].transit_gateway_route_table_id == "tgw-rtb-nonprod"
    error_message = "non-production VPCs are associated with the non-production table"
  }
  assert {
    condition     = toset([for p in aws_ec2_transit_gateway_route_table_propagation.this : p.transit_gateway_route_table_id]) == toset(["tgw-rtb-nonprod", "tgw-rtb-shared"])
    error_message = "non-production propagates into its own table and shared, never production"
  }
  assert {
    condition     = output.networks["vpc-1"].segment == "non-production"
    error_message = "networks carries the segment"
  }
}

run "prod_is_production" {
  command = plan

  variables {
    config_file = "tests/fixtures/prod.yaml"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.this["vpc-1"].ipam_pool_id == "ipam-pool-prod" && aws_vpc_ipam_pool_cidr_allocation.this["vpc-1"].netmask_length == 18
    error_message = "prod: the production pool, /18"
  }
  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.this["vpc-1"].transit_gateway_route_table_id == "tgw-rtb-prod" && toset([for p in aws_ec2_transit_gateway_route_table_propagation.this : p.transit_gateway_route_table_id]) == toset(["tgw-rtb-prod", "tgw-rtb-shared"])
    error_message = "production: associated with its table, propagates into its table and shared, never non-production"
  }
}

run "tooling_is_shared" {
  command = plan

  variables {
    config_file = "tests/fixtures/tooling.yaml"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.this["vpc-1"].ipam_pool_id == "ipam-pool-shared" && aws_ec2_transit_gateway_route_table_association.this["vpc-1"].transit_gateway_route_table_id == "tgw-rtb-shared"
    error_message = "segment: shared takes the shared pool and table"
  }
  assert {
    condition     = toset([for p in aws_ec2_transit_gateway_route_table_propagation.this : p.transit_gateway_route_table_id]) == toset(["tgw-rtb-prod", "tgw-rtb-nonprod", "tgw-rtb-shared"])
    error_message = "shared propagates into all three tables"
  }
}

run "segment_override_only_shared" {
  command = plan

  variables {
    config_file = "tests/fixtures/bad_segment.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "central_has_no_nat_and_defaults_to_tgw" {
  command = plan

  assert {
    condition     = length(module.vpc["vpc-1"].natgw_ids) == 0
    error_message = "central egress: no NAT gateway in the environment VPC"
  }
  assert {
    condition     = keys(aws_route.tgw_routes) == ["vpc-1/0/0.0.0.0/0"] && aws_route.tgw_routes["vpc-1/0/0.0.0.0/0"].transit_gateway_id == "tgw-0abc"
    error_message = "central egress: the private default route is the transit gateway"
  }
}

run "independent_keeps_nat" {
  command = plan

  variables {
    config_file = "tests/fixtures/independent.yaml"
  }

  assert {
    condition     = toset(keys(aws_route.tgw_routes)) == toset(["vpc-1/0/10.0.0.0/8", "vpc-1/0/192.168.0.0/16"])
    error_message = "independent egress: only address_space and on-prem go to the transit gateway"
  }
  assert {
    condition     = module.vpc["vpc-1"].name == "research-sandbox-euw1-vpc-1" && local.vpcs["vpc-1"].enable_nat_gateway
    error_message = "independent egress: the VPC keeps its own NAT"
  }
}

run "shared_rules_associated" {
  command = plan

  variables {
    config_file = "tests/fixtures/forwarding.yaml"
  }

  override_data {
    target = data.aws_route53_resolver_rules.shared[0]
    values = {
      resolver_rule_ids = ["rslvr-rr-1"]
    }
  }

  assert {
    condition     = keys(aws_route53_resolver_rule_association.shared) == ["rslvr-rr-1/vpc-1"]
    error_message = "every shared forwarding rule is associated with every VPC"
  }
}

run "literal_cidr_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/literal_cidr.yaml"
  }

  expect_failures = [aws_vpc_ipam_pool_cidr_allocation.this]
}

run "network_required" {
  command = plan

  variables {
    config_file = "tests/fixtures/no_network.yaml"
  }

  expect_failures = [terraform_data.validation, aws_vpc_ipam_pool_cidr_allocation.this]
}
