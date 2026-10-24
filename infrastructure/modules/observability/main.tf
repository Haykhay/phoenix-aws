# One bucket per group account per region holds the history of every
# cluster's Grafana stack, so it outlives the weekly environment teardown.
# Layout is <signal prefix><cluster name>/...: S3 lifecycle filters only match a
# leading prefix, so the signal comes first to give each its own retention.
# Loki's prefix is "loki-", not "loki/": its storage_prefix may not contain a
# slash and its index sits at the prefix root, so the cluster name has to be
# part of the prefix itself (loki-<cluster>/...).

locals {
  signals = ["mimir", "loki", "tempo", "langfuse"]

  signal_prefixes = {
    mimir    = "mimir/"
    loki     = "loki-"
    tempo    = "tempo/"
    langfuse = "langfuse/"
  }

  retention_defaults = {
    mimir    = 30
    loki     = 14
    tempo    = 7
    langfuse = 30
  }
  retention_days = merge(local.retention_defaults, try(module.context.spec.retention_days, {}))

  bucket_name = "${local.base_name_prefix}-observability-${local.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"
}

# CreatedBy is captured once and frozen: read every run it would record
# whoever last triggered a pipeline.
resource "terraform_data" "created_by" {
  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_kms_key" "this" {
  description         = "${local.bucket_name} encryption"
  enable_key_rotation = true

  tags = { CreatedBy = terraform_data.created_by.output }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.bucket_name}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  tags = { CreatedBy = terraform_data.created_by.output }

  lifecycle {
    # Ephemeral would mean a weekend teardown deletes the history this
    # bucket exists to keep.
    precondition {
      condition     = try(module.context.config.tags.LongLive, false) == true
      error_message = "observability must be LongLive: set tags.LongLive: true so weekend teardowns never touch it."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = local.signals
    content {
      id     = rule.value
      status = "Enabled"

      filter {
        prefix = local.signal_prefixes[rule.value]
      }

      expiration {
        days = local.retention_days[rule.value]
      }

      abort_incomplete_multipart_upload {
        days_after_initiation = 1
      }
    }
  }
}
