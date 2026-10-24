mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/shared.yaml"
}

run "bucket_named_per_account" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "vision-shared-euw1-observability-111111111111"
    error_message = "bucket is <name_prefix>-observability-<account id>"
  }
  assert {
    condition     = output.bucket_name == aws_s3_bucket.this.bucket
    error_message = "bucket_name output is the bucket"
  }
}

run "retention_per_signal" {
  command = plan

  assert {
    condition = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 4 && alltrue([
      for prefix, days in { "mimir/" = 30, "loki-" = 14, "tempo/" = 7, "langfuse/" = 30 } :
      { for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.filter[0].prefix => r.expiration[0].days }[prefix] == days
    ])
    error_message = "default retention: mimir 30, loki 14, tempo 7, langfuse 30 days, keyed by leading signal prefix"
  }
  assert {
    condition     = output.signal_prefixes == { mimir = "mimir/", loki = "loki-", tempo = "tempo/", langfuse = "langfuse/" }
    error_message = "consumers read each signal's leading prefix; a cluster writes under <prefix><cluster name>/"
  }
}

run "retention_override" {
  command = plan

  variables {
    config_file = "tests/fixtures/loki_retention.yaml"
  }

  assert {
    condition = {
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.filter[0].prefix => r.expiration[0].days
    }["loki-"] == 30
    error_message = "spec.retention_days.loki overrides loki"
  }
  assert {
    condition = {
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.filter[0].prefix => r.expiration[0].days
    }["tempo/"] == 7
    error_message = "other signals keep their defaults"
  }
}

run "writer_scoped_to_cluster" {
  command = plan

  assert {
    condition = contains(
      flatten([for s in jsondecode(aws_iam_role_policy.writer_s3["mimir"].policy).Statement : s.Resource]),
      "arn:aws:s3:::vision-shared-euw1-observability-111111111111/mimir/$${aws:PrincipalTag/eks-cluster-name}/*",
    )
    error_message = "mimir may only write under mimir/<its own cluster name>/"
  }
  assert {
    condition = !contains(
      flatten([for s in jsondecode(aws_iam_role_policy.writer_s3["mimir"].policy).Statement : s.Resource]),
      "arn:aws:s3:::vision-shared-euw1-observability-111111111111/loki/$${aws:PrincipalTag/eks-cluster-name}/*",
    )
    error_message = "mimir cannot write into another signal's prefix"
  }
  assert {
    condition = contains(
      flatten([for s in jsondecode(aws_iam_role_policy.writer_s3["loki"].policy).Statement : s.Resource]),
      "arn:aws:s3:::vision-shared-euw1-observability-111111111111/loki-$${aws:PrincipalTag/eks-cluster-name}/*",
    )
    error_message = "loki writes under loki-<cluster name>/: Loki's storage_prefix cannot contain a slash"
  }
  assert {
    condition     = length(aws_iam_role.writer) == 4 && contains(keys(aws_iam_role.writer), "langfuse")
    error_message = "one writer role per signal: mimir, loki, tempo, langfuse"
  }
}

run "pod_identity_trust" {
  command = plan

  assert {
    condition = alltrue([
      for name, role in aws_iam_role.writer :
      jsondecode(role.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com" &&
      contains(jsondecode(role.assume_role_policy).Statement[0].Action, "sts:TagSession")
    ])
    error_message = "writer roles trust EKS Pod Identity (pods.eks.amazonaws.com, AssumeRole + TagSession)"
  }
  assert {
    condition     = jsondecode(aws_iam_role.grafana_cloudwatch.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "Grafana's CloudWatch role trusts EKS Pod Identity"
  }
  assert {
    condition     = aws_iam_role_policy_attachment.grafana_cloudwatch.policy_arn == "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
    error_message = "Grafana reads CloudWatch read-only"
  }
}

run "requires_longlive" {
  command = plan

  variables {
    config_file = "tests/fixtures/ephemeral.yaml"
  }

  expect_failures = [aws_s3_bucket.this]
}
