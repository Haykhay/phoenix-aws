# writer: the model-weights job's Pod Identity role (each k8s-installs
# model-weights unit associates it with its own service account).
# S3 and KMS are separate policies so the S3 one is fully known at plan time
# (the key ARN is not) and its scoping can be reviewed in the plan.

locals {
  pod_identity_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role" "writer" {
  name               = "${local.base_name_prefix}-model-weights-writer"
  assume_role_policy = local.pod_identity_trust
}

# No DeleteObject: a copied version is never mutated or removed by the job.
resource "aws_iam_role_policy" "writer_s3" {
  name = "s3"
  role = aws_iam_role.writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "List", Effect = "Allow", Action = ["s3:ListBucket"], Resource = [local.bucket_arn] },
      { Sid = "ReadWrite", Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = ["${local.bucket_arn}/*"] },
    ]
  })
}

resource "aws_iam_role_policy" "writer_kms" {
  name = "kms"
  role = aws_iam_role.writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
      Resource = [aws_kms_key.this.arn]
    }]
  })
}
