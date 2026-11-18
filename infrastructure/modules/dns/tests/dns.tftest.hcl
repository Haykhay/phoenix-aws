mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/global.yaml"
}

run "dns_zone_names" {
  command = plan

  assert {
    condition     = aws_route53_zone.public["zone-1"].name == "research.example.com"
    error_message = "public zone from the YAML"
  }
  assert {
    condition     = aws_route53_zone.internal["zone-1"].name == "internal.research.example.com"
    error_message = "internal zone from the YAML"
  }
  assert {
    condition     = output.delegations["zone-1"].name == "research.example.com" && output.delegations["zone-1"].parent_zone_name == "example.com"
    error_message = "the parent-zone delegation is an output for the orchestrator, not a write into another account"
  }
}

run "dns_global_only" {
  command = plan

  variables {
    config_file = "tests/fixtures/regional.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "apex_delegation_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/apex_delegated.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "shared_zone_exists_mismatch_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/shared_zone_mismatch.yaml"
  }

  expect_failures = [terraform_data.validation]
}
