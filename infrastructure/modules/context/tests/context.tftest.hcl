variables {
  resource_set = "core-platform"
  config_file  = "tests/fixtures/regional.yaml"
}

run "regional_identity" {
  command = plan

  assert {
    condition     = output.env_id == "research-sandbox"
    error_message = "env_id is <group>-<environment> without a requester"
  }
  assert {
    condition     = output.scope == "eu-west-1"
    error_message = "scope is the YAML region"
  }
  assert {
    condition     = output.name_prefix == "research-sandbox-euw1"
    error_message = "name_prefix is <env_id>-<region code>"
  }
  assert {
    condition     = output.state_key == "research-sandbox/eu-west-1/core-platform/terraform.tfstate"
    error_message = "state_key is <env_id>/<scope>/<resource-set>/terraform.tfstate"
  }
  assert {
    condition     = output.tags["Project"] == "Phoenix"
    error_message = "every resource is tagged Project = Phoenix"
  }
  assert {
    condition     = output.tags["ResourceSet"] == "core-platform"
    error_message = "ResourceSet tag carries the resource set"
  }
  assert {
    condition     = output.role_name == "Terraform-Role"
    error_message = "every account's deploy role has one known name; only the account ID varies"
  }
  assert {
    condition     = !contains(keys(output.tags), "Requester")
    error_message = "Requester tag only appears when a requester is set"
  }
}

run "requester_isolates_names" {
  command = plan

  variables {
    config_file = "tests/fixtures/personal.yaml"
  }

  assert {
    condition     = output.env_id == "research-sandbox-jdoe"
    error_message = "requester is appended to env_id"
  }
  assert {
    condition     = output.name_prefix == "research-sandbox-jdoe-euw1"
    error_message = "requester is part of the name prefix"
  }
  assert {
    condition     = output.tags["Requester"] == "jdoe"
    error_message = "Requester tag is set"
  }
}

run "global_scope_defaults" {
  command = plan

  variables {
    config_file = "tests/fixtures/global.yaml"
  }

  assert {
    condition     = output.scope == "global"
    error_message = "no region means global scope"
  }
  assert {
    condition     = output.region == "us-east-1"
    error_message = "global scope talks to us-east-1 by default"
  }
  assert {
    condition     = output.name_prefix == "research-sandbox"
    error_message = "global names carry no region code"
  }
  assert {
    condition     = output.region_code == null
    error_message = "global scope has no region code"
  }
}

run "missing_owner_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/bad_tags.yaml"
  }

  expect_failures = [output.tags]
}

run "longlive_string_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/longlive_string.yaml"
  }

  expect_failures = [output.tags]
}

run "bad_identifier_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/bad_identifier.yaml"
  }

  expect_failures = [output.name_prefix]
}

run "network_from_core_network_state" {
  command = plan

  variables {
    network = true
  }

  override_data {
    target = data.terraform_remote_state.core_network[0]
    values = {
      outputs = {
        default_vpc_name = "research-sandbox-euw1-vpc-1"
        networks = {
          "research-sandbox-euw1-vpc-1" = { vpc_id = "vpc-123" }
        }
      }
    }
  }

  assert {
    condition     = output.network.vpc_id == "vpc-123"
    error_message = "network is the default VPC from core-network's state"
  }
  assert {
    condition     = output.networks["research-sandbox-euw1-vpc-1"].vpc_id == "vpc-123"
    error_message = "networks exposes every VPC, for consumers that bind per item (core-platform clusters)"
  }
}

run "network_missing_state_is_null" {
  command = plan

  variables {
    network = true
  }

  override_data {
    target = data.terraform_remote_state.core_network[0]
    values = {
      outputs = {}
    }
  }

  assert {
    condition     = output.network == null
    error_message = "a missing core-network state yields null, so a destroy can still plan"
  }
  assert {
    condition     = length(output.networks) == 0
    error_message = "a missing core-network state yields no networks"
  }
}

run "any_region_gets_a_code" {
  command = plan

  variables {
    config_file = "tests/fixtures/apse1.yaml"
  }

  assert {
    condition     = output.region_code == "apse1"
    error_message = "a region outside the old list gets its code from its direction words"
  }
}

run "network_segments" {
  command = plan

  variables {
    config_file = "tests/fixtures/network.yaml"
  }

  assert {
    condition     = output.platform_network.segments == { production = "10.0.0.0/10", "non-production" = "10.64.0.0/10", shared = "10.128.0.0/10" }
    error_message = "three segments, in order, at segment_netmask"
  }
  assert {
    condition     = output.platform_network.first_hub == "eu-west-1"
    error_message = "first hub is hub_regions[0]"
  }
  assert {
    condition     = output.platform_network.egress_mode == "central" && output.platform_network.region_netmask == 13
    error_message = "unset settings take the platform defaults"
  }
}

run "no_network_settings_is_null" {
  command = plan

  assert {
    condition     = output.platform_network == null
    error_message = "a unit without spec.network has no platform network"
  }
}

run "instance_in_state_key" {
  command = plan

  variables {
    config_file = "tests/fixtures/peering.eu-west-1.yaml"
  }

  assert {
    condition     = output.instance == "eu-west-1"
    error_message = "instance comes from <unit>.<instance>.yaml"
  }
  assert {
    condition     = output.state_key == "platform-network/eu-central-1/core-platform.eu-west-1/terraform.tfstate"
    error_message = "the instance is carried into the state key"
  }
}

run "address_space_overlapping_onprem_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/network_overlap.yaml"
  }

  expect_failures = [output.platform_network]
}

run "address_space_too_small_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/network_small.yaml"
  }

  expect_failures = [output.platform_network]
}

run "public_address_space_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/network_public.yaml"
  }

  expect_failures = [output.platform_network]
}

run "dual_dx_needs_two_hubs" {
  command = plan

  variables {
    config_file = "tests/fixtures/network_dual_dx_one_hub.yaml"
  }

  expect_failures = [output.platform_network]
}

run "region_netmask_inside_segment" {
  command = plan

  variables {
    config_file = "tests/fixtures/network_region_netmask.yaml"
  }

  expect_failures = [output.platform_network]
}
