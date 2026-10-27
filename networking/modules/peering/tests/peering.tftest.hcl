mock_provider "aws" {}

mock_provider "aws" {
  alias = "peer"
}

# Region states: eu-west-1 is the first hub.
#   euw1  10.0.0.0/13   10.64.0.0/13  10.128.0.0/13
#   euc1  10.8.0.0/13   10.72.0.0/13  10.136.0.0/13
#   apse1 10.16.0.0/13  10.80.0.0/13  10.144.0.0/13
#   use1  10.24.0.0/13  10.88.0.0/13  10.152.0.0/13

variables {
  config_file = "tests/fixtures/regional_to_hub/peering.eu-west-1.yaml"
}

override_data {
  target = data.terraform_remote_state.local
  values = {
    outputs = {
      transit_gateway_id = "tgw-euc1"
      route_table_ids    = { production = "rtb-euc1-prod", "non-production" = "rtb-euc1-nonprod", shared = "rtb-euc1-shared" }
      blocks             = { production = "10.8.0.0/13", "non-production" = "10.72.0.0/13", shared = "10.136.0.0/13" }
    }
  }
}

override_data {
  target = data.terraform_remote_state.peer
  values = {
    outputs = {
      transit_gateway_id = "tgw-euw1"
      route_table_ids    = { production = "rtb-euw1-prod", "non-production" = "rtb-euw1-nonprod", shared = "rtb-euw1-shared" }
      blocks             = { production = "10.0.0.0/13", "non-production" = "10.64.0.0/13", shared = "10.128.0.0/13" }
    }
  }
}

run "routes_match_the_matrix_on_both_sides" {
  command = plan

  assert {
    condition = toset(keys(aws_ec2_transit_gateway_route.local)) == toset([
      "production/10.0.0.0/13", "non-production/10.64.0.0/13",
      "shared/10.0.0.0/13", "shared/10.64.0.0/13", "shared/10.128.0.0/13",
      "production/10.128.0.0/13", "non-production/10.128.0.0/13",
      "production/192.168.0.0/16", "non-production/192.168.0.0/16",
    ])
    error_message = "this side: same segment to same segment, shared to all, plus the first hub's shared block and on-prem"
  }
  assert {
    condition = toset(keys(aws_ec2_transit_gateway_route.peer)) == toset([
      "production/10.8.0.0/13", "non-production/10.72.0.0/13",
      "shared/10.8.0.0/13", "shared/10.72.0.0/13", "shared/10.136.0.0/13",
    ])
    error_message = "hub side: the matrix only"
  }
  assert {
    condition     = aws_ec2_transit_gateway_route.local["production/10.0.0.0/13"].transit_gateway_route_table_id == "rtb-euc1-prod" && aws_ec2_transit_gateway_route.peer["shared/10.136.0.0/13"].transit_gateway_route_table_id == "rtb-euw1-shared"
    error_message = "routes land in their own side's tables"
  }
}

run "no_cross_segment_route" {
  command = plan

  assert {
    condition = !anytrue([for k, r in aws_ec2_transit_gateway_route.local : (
      (r.transit_gateway_route_table_id == "rtb-euc1-prod" && r.destination_cidr_block == "10.64.0.0/13") ||
      (r.transit_gateway_route_table_id == "rtb-euc1-nonprod" && r.destination_cidr_block == "10.0.0.0/13")
    )])
    error_message = "production never routes to non-production space, and the reverse"
  }
  assert {
    condition = !anytrue([for k, r in aws_ec2_transit_gateway_route.peer : (
      (r.transit_gateway_route_table_id == "rtb-euw1-prod" && r.destination_cidr_block == "10.72.0.0/13") ||
      (r.transit_gateway_route_table_id == "rtb-euw1-nonprod" && r.destination_cidr_block == "10.8.0.0/13")
    )])
    error_message = "the same on the peer side"
  }
}

run "attachments_in_shared" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.local.transit_gateway_route_table_id == "rtb-euc1-shared" && aws_ec2_transit_gateway_route_table_association.peer.transit_gateway_route_table_id == "rtb-euw1-shared"
    error_message = "traffic arriving over the peering is looked up in shared on both sides"
  }
  assert {
    condition     = aws_ec2_transit_gateway_peering_attachment.this.peer_region == "eu-west-1" && aws_ec2_transit_gateway_peering_attachment.this.peer_transit_gateway_id == "tgw-euw1" && aws_ec2_transit_gateway_peering_attachment.this.peer_account_id == "222222222222"
    error_message = "requested from this region to the peer's transit gateway, same account"
  }
}

run "hub_as_requester_puts_hub_routes_on_the_peer_side" {
  command = plan

  variables {
    config_file = "tests/fixtures/hub_to_regional/peering.eu-central-1.yaml"
  }

  override_data {
    target = data.terraform_remote_state.local
    values = {
      outputs = {
        transit_gateway_id = "tgw-euw1"
        route_table_ids    = { production = "rtb-euw1-prod", "non-production" = "rtb-euw1-nonprod", shared = "rtb-euw1-shared" }
        blocks             = { production = "10.0.0.0/13", "non-production" = "10.64.0.0/13", shared = "10.128.0.0/13" }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.peer
    values = {
      outputs = {
        transit_gateway_id = "tgw-euc1"
        route_table_ids    = { production = "rtb-euc1-prod", "non-production" = "rtb-euc1-nonprod", shared = "rtb-euc1-shared" }
        blocks             = { production = "10.8.0.0/13", "non-production" = "10.72.0.0/13", shared = "10.136.0.0/13" }
      }
    }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.local) == 5 && length(aws_ec2_transit_gateway_route.peer) == 9 && contains(keys(aws_ec2_transit_gateway_route.peer), "production/192.168.0.0/16")
    error_message = "the hub routes go on whichever side is not the first hub"
  }
}

run "regional_to_regional_has_no_hub_routes" {
  command = plan

  variables {
    config_file = "tests/fixtures/regional_to_regional/peering.eu-central-1.yaml"
  }

  override_data {
    target = data.terraform_remote_state.local
    values = {
      outputs = {
        transit_gateway_id = "tgw-apse1"
        route_table_ids    = { production = "rtb-apse1-prod", "non-production" = "rtb-apse1-nonprod", shared = "rtb-apse1-shared" }
        blocks             = { production = "10.16.0.0/13", "non-production" = "10.80.0.0/13", shared = "10.144.0.0/13" }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.peer
    values = {
      outputs = {
        transit_gateway_id = "tgw-euc1"
        route_table_ids    = { production = "rtb-euc1-prod", "non-production" = "rtb-euc1-nonprod", shared = "rtb-euc1-shared" }
        blocks             = { production = "10.8.0.0/13", "non-production" = "10.72.0.0/13", shared = "10.136.0.0/13" }
      }
    }
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.local) == 5 && length(aws_ec2_transit_gateway_route.peer) == 5
    error_message = "hub routes go only on peerings with the first hub"
  }
}

run "second_hub_routes_to_tooling" {
  command = plan

  variables {
    config_file = "tests/fixtures/second_hub_to_first/peering.eu-west-1.yaml"
  }

  override_data {
    target = data.terraform_remote_state.local
    values = {
      outputs = {
        transit_gateway_id = "tgw-use1"
        route_table_ids    = { production = "rtb-use1-prod", "non-production" = "rtb-use1-nonprod", shared = "rtb-use1-shared" }
        blocks             = { production = "10.24.0.0/13", "non-production" = "10.88.0.0/13", shared = "10.152.0.0/13" }
      }
    }
  }

  assert {
    condition     = contains(keys(aws_ec2_transit_gateway_route.local), "production/10.128.0.0/13") && contains(keys(aws_ec2_transit_gateway_route.local), "non-production/10.128.0.0/13")
    error_message = "the second hub reaches the tooling VPC through the first hub"
  }
  assert {
    condition     = contains(keys(aws_ec2_transit_gateway_route.local), "production/192.168.0.0/16")
    error_message = "with dual_dx too, the second hub reaches on-prem through the first hub, whose gateway carries both connections"
  }
}

run "second_hub_without_dual_dx_routes_onprem_via_first" {
  command = plan

  variables {
    config_file = "tests/fixtures/second_hub_vpn/peering.eu-west-1.yaml"
  }

  override_data {
    target = data.terraform_remote_state.local
    values = {
      outputs = {
        transit_gateway_id = "tgw-use1"
        route_table_ids    = { production = "rtb-use1-prod", "non-production" = "rtb-use1-nonprod", shared = "rtb-use1-shared" }
        blocks             = { production = "10.24.0.0/13", "non-production" = "10.88.0.0/13", shared = "10.152.0.0/13" }
      }
    }
  }

  assert {
    condition     = contains(keys(aws_ec2_transit_gateway_route.local), "production/192.168.0.0/16")
    error_message = "a second hub without its own on-prem connection reaches on-prem through the first hub"
  }
}

run "both_regions_must_exist" {
  command = plan

  override_data {
    target = data.terraform_remote_state.peer
    values = {
      outputs = {}
    }
  }

  expect_failures = [aws_ec2_transit_gateway_peering_attachment.this]
}
