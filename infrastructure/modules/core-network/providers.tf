provider "aws" {
  region                      = module.context.region
  allowed_account_ids         = module.context.floci ? null : [module.context.account_id]
  skip_credentials_validation = module.context.floci
  skip_requesting_account_id  = module.context.floci
  skip_metadata_api_check     = module.context.floci

  default_tags { tags = module.context.tags }

  # Owned by aws_ec2_tag.internal_elb, not by the subnets' own tags -- without
  # this the VPC module's aws_subnet would remove it on every apply.
  # aws_ec2_tag itself does not honour ignore_tags.
  ignore_tags { keys = ["kubernetes.io/role/internal-elb"] }
}

