# One bucket per group account per region holds every model's weights at
# <model>/<version>/. It outlives the weekly environment teardown: weights are
# copied once (model-weights) and every cluster's FSx cache (model-cache)
# loads from here.

locals {
  bucket_name = "${local.base_name_prefix}-model-weights-${local.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"

  # Buckets model-weights may copy from (s3 sources, any account). Each one's
  # bucket policy must grant the writer role too.
  source_buckets = try(module.context.spec.source_buckets, [])
}

# CreatedBy is captured once and frozen: read every run it would record
# whoever last triggered a pipeline.
resource "terraform_data" "created_by" {
  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

# Ephemeral would mean a weekend teardown deletes every copied model.
resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = try(module.context.config.tags.LongLive, false) == true
      error_message = "model-store must be LongLive: set tags.LongLive: true so weekend teardowns never touch the weights."
    }
  }
}

# FSx reads the bucket through its own service-linked role (one per file
# system, AWSServiceRoleForFSxS3Access_<fs id>), not an IAM role we attach, so
# the key policy has to let that role decrypt.
resource "aws_kms_key" "this" {
  description         = "${local.bucket_name} encryption"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = ["kms:*"]
        Resource  = "*"
      },
      {
        Sid       = "FsxLazyLoad"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:PrincipalAccount" = local.account_id }
          ArnLike      = { "aws:PrincipalArn" = "arn:aws:iam::${local.account_id}:role/aws-service-role/s3.data-source.lustre.fsx.amazonaws.com/AWSServiceRoleForFSxS3Access_*" }
        }
      },
    ]
  })

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
    prevent_destroy = true
  }

  depends_on = [terraform_data.validation]
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
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
