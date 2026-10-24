mock_provider "aws" {}

mock_provider "aws" {
  alias = "management"
}

variables {
  config_file = "tests/fixtures/global.yaml"
}

run "dns_zone_names" {
  command = plan

  assert {
    condition     = aws_route53_zone.public["zone-1"].name == "vision.example.com"
    error_message = "public zone from the YAML"
  }
  assert {
    condition     = aws_route53_zone.internal["zone-1"].name == "internal.vision.example.com"
    error_message = "internal zone from the YAML"
  }
  assert {
    condition     = aws_route53_record.public_ns["zone-1"].name == "vision.example.com"
    error_message = "public zone is delegated into its parent through the management provider"
  }
}

run "dns_global_only" {
  command = plan

  variables {
    config_file = "tests/fixtures/regional.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "delegation_requires_management_role" {
  command = plan

  variables {
    config_file = "tests/fixtures/no_management.yaml"
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

run "management_account_id_must_be_valid" {
  command = plan

  variables {
    config_file = "tests/fixtures/bad_management_account.yaml"
  }

  expect_failures = [terraform_data.validation]
}
