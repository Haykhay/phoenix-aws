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

  # Owned by aws_ec2_tag.internal_elb, not by the subnets' own tags -- without
  # this the VPC module's aws_subnet would remove it on every apply.
  # aws_ec2_tag itself does not honour ignore_tags.
  ignore_tags { keys = ["kubernetes.io/role/internal-elb"] }
}

# The networking account owns the transit gateways and their route tables:
# associations and propagations are made from it. `spec.providers.network.
# account_id`; the role is that account's deploy role (module.context.role_name).
provider "aws" {
  alias               = "network"
  region              = module.context.region
  allowed_account_ids = local.network_account_id == null ? null : [local.network_account_id]

  dynamic "assume_role" {
    for_each = local.network_role_arn == null ? [] : [local.network_role_arn]
    content { role_arn = assume_role.value }
  }

  default_tags { tags = module.context.tags }
}
