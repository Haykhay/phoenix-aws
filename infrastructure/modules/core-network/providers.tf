provider "aws" {
  region              = module.context.region
  allowed_account_ids = [module.context.account_id]

  default_tags { tags = module.context.tags }

  # Owned by aws_ec2_tag.internal_elb, not by the subnets' own tags -- without
  # this the VPC module's aws_subnet would remove it on every apply.
  # aws_ec2_tag itself does not honour ignore_tags.
  ignore_tags { keys = ["kubernetes.io/role/internal-elb"] }
}

# The networking account owns the transit gateways; its eu-west-1 hub carries
# the cross-region peering routes. `spec.providers.network.account_id`; the role
# is that account's deploy role (module.context.role_name).
# Without one (no TGW features) these fall back to the workload credentials and
# nothing uses them.
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

provider "aws" {
  alias               = "network_dublin"
  region              = "eu-west-1"
  allowed_account_ids = local.network_account_id == null ? null : [local.network_account_id]

  dynamic "assume_role" {
    for_each = local.network_role_arn == null ? [] : [local.network_role_arn]
    content { role_arn = assume_role.value }
  }

  default_tags { tags = module.context.tags }
}
