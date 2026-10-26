# The networking account, in IPAM's home region (the YAML's global_region:
# the first hub).
provider "aws" {
  region              = module.context.region
  allowed_account_ids = [module.context.account_id]

  default_tags { tags = module.context.tags }
}
