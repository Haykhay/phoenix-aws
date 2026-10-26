mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/shared.yaml"
}

run "ecr_rule_points_at_hub" {
  command = plan

  assert {
    condition     = aws_ecr_pull_through_cache_rule.this.upstream_registry_url == "999999999999.dkr.ecr.eu-west-1.amazonaws.com"
    error_message = "the cache rule pulls from the hub registry in this region by default"
  }
  assert {
    condition     = aws_ecr_pull_through_cache_rule.this.ecr_repository_prefix == "artifactory"
    error_message = "cached repositories live under the artifactory/ prefix by default"
  }
  assert {
    condition     = aws_ecr_pull_through_cache_rule.this.custom_role_arn == "arn:aws:iam::111111111111:role/research-shared-euw1-ecr-pull-through"
    error_message = "the rule pulls with this account's pull-through role"
  }
  assert {
    condition     = output.registry_url_prefix == "111111111111.dkr.ecr.eu-west-1.amazonaws.com/artifactory"
    error_message = "workloads pull from <account>.dkr.ecr.<region>.amazonaws.com/<prefix>"
  }
}

run "ecr_template_encrypts" {
  command = plan

  assert {
    condition     = aws_ecr_repository_creation_template.this.prefix == "artifactory"
    error_message = "the template applies to the cache prefix"
  }
  assert {
    condition     = toset(aws_ecr_repository_creation_template.this.applied_for) == toset(["PULL_THROUGH_CACHE"])
    error_message = "the template applies to pull-through repositories"
  }
  assert {
    condition     = aws_ecr_repository_creation_template.this.encryption_configuration[0].encryption_type == "KMS"
    error_message = "cached repositories are KMS-encrypted"
  }
}

run "ecr_role_trusts_pull_through" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.pull_through.assume_role_policy).Statement[0].Principal.Service == "pullthroughcache.ecr.amazonaws.com"
    error_message = "ECR's pull-through service assumes the role"
  }
}

run "ecr_requires_hub" {
  command = plan

  variables {
    config_file = "tests/fixtures/no_hub.yaml"
  }

  expect_failures = [aws_ecr_pull_through_cache_rule.this]
}
