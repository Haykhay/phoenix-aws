# The networking account in the first hub region (this unit's region), and in
# the second hub region for dual_dx (the first hub again otherwise, unused).
provider "aws" {
  region              = module.context.region
  allowed_account_ids = [module.context.account_id]

  default_tags { tags = module.context.tags }
}

provider "aws" {
  alias               = "second"
  region              = coalesce(try(module.context.platform_network.hub_regions[1], null), module.context.region)
  allowed_account_ids = [module.context.account_id]

  default_tags { tags = module.context.tags }
}
