# Roles for EKS Pod Identity. core-platform associates them with each
# cluster's service accounts. Pod Identity tags every session with
# eks-cluster-name, so one role per signal serves every cluster in the account
# while each cluster can only touch its own <signal prefix><cluster name>/ path
# (mimir/<cluster>/, loki-<cluster>/, tempo/<cluster>/, langfuse/<cluster>/).

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
  for_each = toset(local.signals)

  name               = "${local.base_name_prefix}-${each.key}"
  assume_role_policy = local.pod_identity_trust
}

# S3 and KMS are separate policies so the S3 one is fully known at plan time
# (the key ARN is not) and its scoping can be reviewed in the plan.
resource "aws_iam_role_policy" "writer_s3" {
  for_each = toset(local.signals)

  name = "s3-${each.key}"
  role = aws_iam_role.writer[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListOwnPrefix"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.bucket_arn]
        Condition = {
          StringLike = { "s3:prefix" = ["${local.signal_prefixes[each.key]}$${aws:PrincipalTag/eks-cluster-name}/*"] }
        }
      },
      {
        Sid      = "ReadWriteOwnPrefix"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.bucket_arn}/${local.signal_prefixes[each.key]}$${aws:PrincipalTag/eks-cluster-name}/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "writer_kms" {
  for_each = toset(local.signals)

  name = "kms"
  role = aws_iam_role.writer[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
      Resource = [aws_kms_key.this.arn]
    }]
  })
}

# Grafana's CloudWatch data source: AWS service metrics (RDS, ElastiCache, MSK,
# ALB) that no in-cluster collector sees.
resource "aws_iam_role" "grafana_cloudwatch" {
  name               = "${local.base_name_prefix}-grafana-cloudwatch"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  role       = aws_iam_role.grafana_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}
