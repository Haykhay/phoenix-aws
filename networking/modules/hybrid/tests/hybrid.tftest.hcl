mock_provider "aws" {}

mock_provider "aws" {
  alias = "second"
}

variables {
  config_file = "tests/fixtures/vpn.yaml"
}

override_data {
  target = data.terraform_remote_state.first
  values = {
    outputs = {
      transit_gateway_id = "tgw-euw1"
      amazon_side_asn    = 64512
      route_table_ids    = { production = "rtb-euw1-prod", "non-production" = "rtb-euw1-nonprod", shared = "rtb-euw1-shared" }
    }
  }
}

run "vpn_plans_only_vpn" {
  command = plan

  assert {
    condition     = length(aws_vpn_connection.this) == 1 && length(aws_dx_gateway.this) == 0 && length(aws_dx_transit_virtual_interface.first) == 0
    error_message = "vpn: one VPN, no Direct Connect"
  }
  assert {
    condition     = aws_vpn_connection.this[0].static_routes_only == false && aws_vpn_connection.this[0].transit_gateway_id == "tgw-euw1" && aws_customer_gateway.this[0].bgp_asn == "65010"
    error_message = "BGP over two tunnels to the first hub's transit gateway"
  }
  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.vpn[0].transit_gateway_route_table_id == "rtb-euw1-shared" && toset([for p in aws_ec2_transit_gateway_route_table_propagation.vpn : p.transit_gateway_route_table_id]) == toset(["rtb-euw1-prod", "rtb-euw1-nonprod", "rtb-euw1-shared"])
    error_message = "on-prem sits in shared and its routes propagate into all three tables"
  }
}

run "dx_vpn_plans_both" {
  command = plan

  variables {
    config_file = "tests/fixtures/dx_vpn.yaml"
  }

  assert {
    condition     = length(aws_vpn_connection.this) == 1 && length(aws_dx_gateway.this) == 1 && length(aws_dx_transit_virtual_interface.first) == 1 && length(aws_dx_transit_virtual_interface.second) == 0 && length(aws_dx_gateway_association.this) == 1
    error_message = "dx_vpn: one Direct Connect plus the backup VPN"
  }
  assert {
    condition     = toset(aws_dx_gateway_association.this[0].allowed_prefixes) == toset(["10.0.0.0/10", "10.64.0.0/10", "10.128.0.0/10"]) && aws_dx_gateway_association.this[0].associated_gateway_id == "tgw-euw1"
    error_message = "the gateway advertises the three segment summaries from the first hub"
  }
  assert {
    condition     = aws_dx_transit_virtual_interface.first[0].connection_id == "dxcon-example1" && aws_dx_transit_virtual_interface.first[0].vlan == 101 && aws_dx_gateway.this[0].amazon_side_asn == "64600"
    error_message = "the virtual interface sits on the adopter's connection"
  }
}

run "dual_dx_fails_over_inside_one_gateway" {
  command = plan

  variables {
    config_file = "tests/fixtures/dual_dx.yaml"
  }

  override_resource {
    target          = aws_dx_gateway.this
    override_during = plan
    values = {
      id = "dxgw-onprem"
    }
  }

  assert {
    condition     = length(aws_vpn_connection.this) == 0 && length(aws_dx_gateway.this) == 1 && length(aws_dx_transit_virtual_interface.first) == 1 && length(aws_dx_transit_virtual_interface.second) == 1
    error_message = "dual_dx: one Direct Connect gateway carrying both connections' virtual interfaces, no VPN"
  }
  assert {
    condition     = aws_dx_transit_virtual_interface.second[0].connection_id == "dxcon-example2" && aws_dx_transit_virtual_interface.first[0].dx_gateway_id == "dxgw-onprem" && aws_dx_transit_virtual_interface.second[0].dx_gateway_id == "dxgw-onprem"
    error_message = "both virtual interfaces sit on the same gateway, so it fails over between them by BGP"
  }
  assert {
    condition     = length(aws_dx_gateway_association.this) == 1 && aws_dx_gateway_association.this[0].associated_gateway_id == "tgw-euw1"
    error_message = "one association, to the first hub: AWS forbids overlapping allowed prefixes across transit gateway associations of one gateway"
  }
  assert {
    condition     = output.onprem.dx.primary.connection_id == "dxcon-example1" && output.onprem.dx.secondary.connection_id == "dxcon-example2"
    error_message = "the handoff names the primary and the secondary (prepended) connection"
  }
}

run "dual_dx_needs_two_connections" {
  command = plan

  variables {
    config_file = "tests/fixtures/dual_dx_one_connection.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "vpn_needs_a_customer_gateway" {
  command = plan

  variables {
    config_file = "tests/fixtures/vpn_without_gateway.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "none_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/none.yaml"
  }

  assert {
    condition     = length(aws_vpn_connection.this) + length(aws_customer_gateway.this) + length(aws_dx_gateway.this) + length(aws_dx_transit_virtual_interface.first) + length(aws_dx_transit_virtual_interface.second) == 0
    error_message = "hybrid none: nothing"
  }
}
