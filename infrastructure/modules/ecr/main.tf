# Pull-through cache spoke (hub and spoke). The hub — one central ECR filled
# from the company's Artifactory by a scheduled sync — lives outside this repo:
# ECR's pull-through cache cannot use Artifactory as an upstream, but it can use
# another ECR. Each group account caches from the hub on demand, so it holds
# only what its workloads actually pull, and AWS refreshes cached tags from the
# hub at least daily.
#
# Workloads pull <account>.dkr.ecr.<region>.amazonaws.com/<cache prefix>/<repo>:<tag>.

locals {
  defaults = {
    enabled      = true
    cache_prefix = "artifactory"
    hub          = {}

    # Lifecycle of cached repositories.
    untagged_expiry_days = 7
    keep_images          = 30
  }
  config = merge(local.defaults, module.context.spec)

  hub_account_id        = try(tostring(local.config.hub.account_id), null)
  hub_region            = try(local.config.hub.region, local.region)
  hub_repository_prefix = try(local.config.hub.repository_prefix, null)
  hub_registry          = "${coalesce(local.hub_account_id, "000000000000")}.dkr.ecr.${local.hub_region}.amazonaws.com"

  cache_prefix = local.config.cache_prefix
  role_name    = "${local.base_name_prefix}-ecr-pull-through"
  # Built rather than read from the role, so the rule's role is known at plan.
  role_arn = "arn:aws:iam::${local.account_id}:role/${local.role_name}"
}

# CreatedBy is captured once and frozen.
resource "terraform_data" "created_by" {
  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_kms_key" "ecr" {
  description         = "${local.base_name_prefix} ECR pull-through cache"
  enable_key_rotation = true

  tags = { CreatedBy = terraform_data.created_by.output }
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${local.base_name_prefix}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_ecr_pull_through_cache_rule" "this" {
  ecr_repository_prefix      = local.cache_prefix
  upstream_registry_url      = local.hub_registry
  upstream_repository_prefix = local.hub_repository_prefix
  custom_role_arn            = local.role_arn

  depends_on = [aws_iam_role_policy.pull_through]

  lifecycle {
    precondition {
      condition     = local.hub_account_id != null && can(regex("^[0-9]{12}$", local.hub_account_id))
      error_message = "spec.hub.account_id must be the 12-digit account of the central ECR hub this account caches from."
    }
  }
}

# Repositories ECR creates on first pull get these settings.
resource "aws_ecr_repository_creation_template" "this" {
  prefix               = local.cache_prefix
  description          = "Pull-through cache of the central ECR hub"
  applied_for          = ["PULL_THROUGH_CACHE"]
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = local.config.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = local.config.keep_images
        }
        action = { type = "expire" }
      },
    ]
  })

  resource_tags = merge(module.context.tags, { CreatedBy = terraform_data.created_by.output })
}
