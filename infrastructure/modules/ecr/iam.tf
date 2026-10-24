# The role ECR assumes to pull from the hub in another account. The hub's
# registry policy must allow it (hub side, outside this repo).
resource "aws_iam_role" "pull_through" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pullthroughcache.ecr.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "pull_through" {
  name = "pull-from-hub"
  role = aws_iam_role.pull_through.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Auth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "ReadHub"
        Effect = "Allow"
        Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = [
          "arn:aws:ecr:${local.hub_region}:${coalesce(local.hub_account_id, "000000000000")}:repository/${local.hub_repository_prefix == null ? "" : local.hub_repository_prefix}*",
        ]
      },
    ]
  })
}

# The first pull of an image creates its cache repository, which needs more
# than plain pull rights. Attach to node roles through core-platform's
# node_role_additional_policies.
resource "aws_iam_policy" "node_pull" {
  name        = "${local.base_name_prefix}-ecr-pull-through"
  description = "Pull from, and populate on first pull, the ${local.cache_prefix}/ pull-through cache"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:BatchImportUpstreamImage",
        "ecr:CreateRepository",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
      ]
      Resource = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.cache_prefix}/*"]
    }]
  })
}
