# The networking account, in this unit's region.
provider "aws" {
  region                      = module.context.region
  allowed_account_ids         = module.context.floci ? null : [module.context.account_id]
  skip_credentials_validation = module.context.floci
  skip_requesting_account_id  = module.context.floci
  skip_metadata_api_check     = module.context.floci

  default_tags { tags = module.context.tags }
}
