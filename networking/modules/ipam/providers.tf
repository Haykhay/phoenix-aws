# The networking account, in IPAM's home region (the YAML's global_region:
# the first hub).
provider "aws" {
  region              = module.context.region
  allowed_account_ids = [module.context.account_id]
  assume_role { role_arn = module.context.deploy_role_arn }

  default_tags { tags = module.context.tags }
}
