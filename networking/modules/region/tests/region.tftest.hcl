mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/central.yaml"
}

override_data {
  target = data.terraform_remote_state.ipam
  values = {
    outputs = {
      regional_blocks = {
        "eu-west-1" = { production = "10.0.0.0/13", "non-production" = "10.64.0.0/13", shared = "10.128.0.0/13" }
      }
      regional_pool_ids = {
        "eu-west-1" = { production = "ipam-pool-prod", "non-production" = "ipam-pool-nonprod", shared = "ipam-pool-shared" }
      }
    }
  }
}

override_data {
  target = data.aws_availability_zones.this
  values = {
    names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  }
}

run "transit_gateway_is_explicit" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable" && aws_ec2_transit_gateway.this.default_route_table_propagation == "disable" && aws_ec2_transit_gateway.this.auto_accept_shared_attachments == "enable"
    error_message = "no implicit association or propagation; shared attachments auto-accepted"
  }
  assert {
    condition     = toset(keys(aws_ec2_transit_gateway_route_table.this)) == toset(["production", "non-production", "shared"])
    error_message = "three route tables"
  }
  assert {
    condition     = toset([for p in aws_ram_principal_association.tgw : p.principal]) == toset(["arn:aws:organizations::999999999999:organization/o-example"]) && aws_ram_resource_share.tgw.allow_external_principals == false
    error_message = "the transit gateway is shared with share_with, inside the organisation"
  }
}

run "cross_segment_blackholes" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_route.blackhole["production/10.64.0.0/10"].blackhole && aws_ec2_transit_gateway_route.blackhole["non-production/10.0.0.0/10"].blackhole
    error_message = "each segment table blackholes the other segment"
  }
  assert {
    condition     = !contains(keys(aws_ec2_transit_gateway_route.blackhole), "shared/10.0.0.0/10") && !contains(keys(aws_ec2_transit_gateway_route.blackhole), "shared/10.64.0.0/10")
    error_message = "shared reaches both segments: no segment blackhole there"
  }
}

run "address_space_blackholed_everywhere" {
  command = plan

  assert {
    condition     = alltrue([for t in ["production", "non-production", "shared"] : aws_ec2_transit_gateway_route.blackhole["${t}/10.0.0.0/8"].blackhole])
    error_message = "unprovisioned private space is dropped, never looped through egress"
  }
}

run "central_default_routes" {
  command = plan

  assert {
    condition     = toset(keys(aws_ec2_transit_gateway_route.default)) == toset(["production", "non-production", "shared"]) && length(module.egress_vpc) == 1
    error_message = "central: 0.0.0.0/0 -> egress attachment in all three tables, egress VPC built"
  }
  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.egress[0].transit_gateway_default_route_table_association == false && aws_ec2_transit_gateway_vpc_attachment.egress[0].transit_gateway_default_route_table_propagation == false
    error_message = "egress attachment is associated explicitly and never propagated"
  }
  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.egress[0].ipam_pool_id == "ipam-pool-shared" && aws_vpc_ipam_pool_cidr_allocation.egress[0].netmask_length == 24
    error_message = "egress VPC is a /24 from the region's shared pool"
  }
  assert {
    condition     = aws_route.egress_return[0].destination_cidr_block == "10.0.0.0/8"
    error_message = "the egress VPC sends address_space back to the transit gateway"
  }
}

run "independent_has_no_egress" {
  command = plan

  variables {
    config_file = "tests/fixtures/independent.yaml"
  }

  assert {
    condition     = length(module.egress_vpc) == 0 && length(aws_ec2_transit_gateway_route.default) == 0 && length(aws_ec2_transit_gateway_vpc_attachment.egress) == 0
    error_message = "independent: no egress VPC, no default route"
  }
}

run "region_must_have_joined_ipam" {
  command = plan

  variables {
    config_file = "tests/fixtures/not_joined.yaml"
  }

  expect_failures = [aws_ec2_transit_gateway.this, aws_vpc_ipam_pool_cidr_allocation.egress]
}
