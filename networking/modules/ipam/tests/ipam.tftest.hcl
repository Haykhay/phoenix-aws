mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/one_region.yaml"
}

run "segment_pools" {
  command = plan

  assert {
    condition     = toset(keys(aws_vpc_ipam_pool.segment)) == toset(["production", "non-production", "shared"])
    error_message = "one top pool per segment"
  }
  assert {
    condition     = aws_vpc_ipam_pool_cidr.segment["non-production"].cidr == "10.64.0.0/10"
    error_message = "each segment pool holds its segment block"
  }
}

run "adding_a_region_adds_three_regional_pools" {
  command = plan

  variables {
    config_file = "tests/fixtures/two_regions.yaml"
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.regional) == 6 && alltrue([for k, v in aws_vpc_ipam_pool_cidr.regional : v.netmask_length == 13])
    error_message = "three regional pools per region, each region_netmask"
  }
  assert {
    condition     = aws_vpc_ipam_pool.regional["eu-central-1/production"].locale == "eu-central-1" && aws_vpc_ipam_pool.regional["eu-central-1/production"].description == "production/eu-central-1"
    error_message = "regional pools are bound to their region and described <segment>/<region>"
  }
  assert {
    condition     = aws_vpc_ipam_pool.regional["eu-central-1/production"].allocation_min_netmask_length == 17 && aws_vpc_ipam_pool.regional["eu-central-1/production"].allocation_max_netmask_length == 22
    error_message = "VPCs take /17 to /22 from a regional pool"
  }
}

run "operating_regions_follow_regions" {
  command = plan

  variables {
    config_file = "tests/fixtures/two_regions.yaml"
  }

  assert {
    condition     = toset([for r in aws_vpc_ipam.this.operating_regions : r.region_name]) == toset(["eu-west-1", "eu-central-1"])
    error_message = "IPAM operates in every joined region"
  }
}

run "regional_pools_shared" {
  command = plan

  variables {
    config_file = "tests/fixtures/two_regions.yaml"
  }

  assert {
    condition     = length(aws_ram_resource_association.regional) == 6 && toset([for p in aws_ram_principal_association.this : p.principal]) == toset(["arn:aws:organizations::999999999999:organization/o-example"])
    error_message = "every regional pool is shared with share_with"
  }
  assert {
    condition     = aws_ram_resource_share.this.allow_external_principals == false
    error_message = "pools never leave the organisation"
  }
}

run "home_region_must_operate" {
  command = plan

  variables {
    config_file = "tests/fixtures/home_missing.yaml"
  }

  expect_failures = [aws_vpc_ipam.this]
}
