# Both sides are the networking account: this unit's region (the requester)
# and the peer region (the instance in the file name, the accepter).
provider "aws" {
  region              = module.context.region
  allowed_account_ids = [module.context.account_id]
  assume_role { role_arn = module.context.deploy_role_arn }

  default_tags { tags = module.context.tags }
}

provider "aws" {
  alias               = "peer"
  region              = module.context.instance
  allowed_account_ids = [module.context.account_id]
  assume_role { role_arn = module.context.deploy_role_arn }

  default_tags { tags = module.context.tags }
}
