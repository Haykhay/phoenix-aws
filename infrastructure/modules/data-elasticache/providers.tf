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
