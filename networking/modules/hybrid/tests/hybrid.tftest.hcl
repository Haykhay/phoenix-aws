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

override_data {
  target = data.terraform_remote_state.second
  values = {
    outputs = {
      transit_gateway_id = "tgw-use1"
      amazon_side_asn    = 64513
      route_table_ids    = { production = "rtb-use1-prod", "non-production" = "rtb-use1-nonprod", shared = "rtb-use1-shared" }
    }
  }
}

run "vpn_plans_only_vpn" {
  command = plan

  assert {
    condition     = length(aws_vpn_connection.this) == 1 && length(aws_dx_gateway.first) == 0 && length(aws_dx_transit_virtual_interface.first) == 0
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
    condition     = length(aws_vpn_connection.this) == 1 && length(aws_dx_gateway.first) == 1 && length(aws_dx_gateway.second) == 0 && length(aws_dx_transit_virtual_interface.first) == 1 && length(aws_dx_transit_virtual_interface.second) == 0 && length(aws_dx_gateway_association.first) == 1 && length(aws_dx_gateway_association.second) == 0
    error_message = "dx_vpn: one Direct Connect plus the backup VPN"
  }
  assert {
    condition     = toset(aws_dx_gateway_association.first[0].allowed_prefixes) == toset(["10.0.0.0/10", "10.64.0.0/10", "10.128.0.0/10"]) && aws_dx_gateway_association.first[0].associated_gateway_id == "tgw-euw1"
    error_message = "the gateway advertises the three segment summaries from the first hub"
  }
  assert {
    condition     = aws_dx_transit_virtual_interface.first[0].connection_id == "dxcon-example1" && aws_dx_transit_virtual_interface.first[0].vlan == 101 && aws_dx_gateway.first[0].amazon_side_asn == "64600"
    error_message = "the virtual interface sits on the adopter's connection"
  }
}

run "dual_dx_associates_both_hubs" {
  command = plan

  variables {
    config_file = "tests/fixtures/dual_dx.yaml"
  }

  assert {
    condition     = length(aws_vpn_connection.this) == 0 && length(aws_dx_gateway.first) == 1 && length(aws_dx_gateway.second) == 1 && length(aws_dx_transit_virtual_interface.first) == 1 && length(aws_dx_transit_virtual_interface.second) == 1
    error_message = "dual_dx: a Direct Connect gateway and a virtual interface per hub, no VPN"
  }
  assert {
    condition     = aws_dx_gateway_association.first[0].associated_gateway_id == "tgw-euw1" && aws_dx_gateway_association.second[0].associated_gateway_id == "tgw-use1" && aws_dx_transit_virtual_interface.second[0].connection_id == "dxcon-example2"
    error_message = "each hub's connection lands on that hub's transit gateway"
  }
  assert {
    condition     = toset(aws_dx_gateway_association.second[0].allowed_prefixes) == toset(["10.0.0.0/10", "10.64.0.0/10", "10.128.0.0/10"])
    error_message = "both gateways advertise the segment summaries; separate gateways, so no overlap within one"
  }
  assert {
    condition     = output.onprem.dx.primary.connection_id == "dxcon-example1" && output.onprem.dx.primary.hub == "eu-west-1" && output.onprem.dx.secondary.connection_id == "dxcon-example2"
    error_message = "the first hub's connection is the primary: every region but the second hub reaches on-prem through it"
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
    condition     = length(aws_vpn_connection.this) + length(aws_customer_gateway.this) + length(aws_dx_gateway.first) + length(aws_dx_gateway.second) + length(aws_dx_transit_virtual_interface.first) + length(aws_dx_transit_virtual_interface.second) == 0
    error_message = "hybrid none: nothing"
  }
}
