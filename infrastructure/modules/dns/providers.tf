provider "aws" {
  region                      = module.context.region
  allowed_account_ids         = module.context.floci ? null : [module.context.account_id]
  skip_credentials_validation = module.context.floci
  skip_requesting_account_id  = module.context.floci
  skip_metadata_api_check     = module.context.floci
  dynamic "assume_role" {
    for_each = module.context.floci ? [] : [module.context.deploy_role_arn]
    content { role_arn = assume_role.value }
  }

  default_tags { tags = module.context.tags }
}

# The management account: the delegated admin account holding the parent zones
# the public zones are delegated into (not the AWS Organizations management
# account). `spec.providers.management.account_id`; the role is that account's
# deploy role (module.context.role_name), assumed from the pipeline's own
# credentials. Without one (no delegation) it falls back to
# those credentials and nothing uses it.
provider "aws" {
  alias               = "management"
  region              = module.context.region
  allowed_account_ids = local.management_account_id == null ? null : [local.management_account_id]

  dynamic "assume_role" {
    for_each = local.management_role_arn == null ? [] : [local.management_role_arn]
    content { role_arn = assume_role.value }
  }

  default_tags { tags = module.context.tags }
}
