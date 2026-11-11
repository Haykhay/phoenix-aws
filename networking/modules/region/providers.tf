# The networking account, in this unit's region.
provider "aws" {
  region              = module.context.region
  allowed_account_ids = [module.context.account_id]
  assume_role { role_arn = module.context.deploy_role_arn }

  default_tags { tags = module.context.tags }
}
