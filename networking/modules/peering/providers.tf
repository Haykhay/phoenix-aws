# Both sides are the networking account: this unit's region (the requester)
# and the peer region (the instance in the file name, the accepter).
provider "aws" {
  region              = module.context.region
  allowed_account_ids = [module.context.account_id]

  default_tags { tags = module.context.tags }
}

provider "aws" {
  alias               = "peer"
  region              = module.context.instance
  allowed_account_ids = [module.context.account_id]

  default_tags { tags = module.context.tags }
}
