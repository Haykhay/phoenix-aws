mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/model-store.yaml"
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "research-shared-euw1-model-weights-111111111111"
    error_message = "one weights bucket per group account and region: <name_prefix>-model-weights-<account id>"
  }
  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled" && aws_s3_bucket_public_access_block.this.block_public_acls
    error_message = "weights are versioned and never public"
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "weights are encrypted with the bucket's own KMS key"
  }
  assert {
    condition     = jsondecode(aws_iam_role.writer.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "the writer role is for EKS Pod Identity"
  }
  assert {
    condition = alltrue([
      for a in ["s3:PutObject", "s3:GetObject"] :
      contains(jsondecode(aws_iam_role_policy.writer_s3.policy).Statement[1].Action, a)
    ]) && !contains(jsondecode(aws_iam_role_policy.writer_s3.policy).Statement[1].Action, "s3:DeleteObject")
    error_message = "the writer adds weights and never deletes them (versions are immutable)"
  }
  assert {
    condition = anytrue([
      for st in jsondecode(aws_kms_key.this.policy).Statement :
      st.Action == ["kms:Decrypt", "kms:DescribeKey"] && strcontains(jsonencode(st.Condition), "AWSServiceRoleForFSxS3Access")
    ])
    error_message = "FSx's S3 service-linked role can decrypt, so model-cache can lazy-load the weights"
  }
}

run "long_live_required" {
  command = plan

  variables {
    config_file = "tests/fixtures/model-store.ephemeral.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "source_buckets_readable" {
  command = plan

  variables {
    config_file = "tests/fixtures/model-store.sources.yaml"
  }

  assert {
    condition = alltrue([
      contains(jsondecode(aws_iam_role_policy.writer_s3.policy).Statement[2].Resource, "arn:aws:s3:::acme-research-models"),
      contains(jsondecode(aws_iam_role_policy.writer_s3.policy).Statement[2].Resource, "arn:aws:s3:::acme-research-models/*"),
      jsondecode(aws_iam_role_policy.writer_s3.policy).Statement[2].Action == ["s3:ListBucket", "s3:GetObject"],
      jsondecode(aws_iam_role_policy.writer_s3.policy).Statement[3].Condition.StringLike["kms:ViaService"] == "s3.*.amazonaws.com",
    ])
    error_message = "s3 sources (any account) are readable by the copy role, KMS-encrypted ones through S3; their bucket policy must also grant it"
  }
}

run "no_source_buckets_by_default" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.writer_s3.policy).Statement) == 2
    error_message = "the copy role reads no other bucket unless one is named"
  }
}
