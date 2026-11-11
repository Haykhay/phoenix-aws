# Both sides' region units, from the networking state bucket.
data "terraform_remote_state" "local" {
  backend = "s3"

  config = {
    bucket     = module.context.state.bucket
    region     = module.context.state.region
    kms_key_id = module.context.state.kms_key_id
    key        = "platform-network/${local.region}/region/terraform.tfstate"
    assume_role = {
      role_arn = module.context.deploy_role_arn
    }
  }

  defaults = {}
}

data "terraform_remote_state" "peer" {
  backend = "s3"

  config = {
    bucket     = module.context.state.bucket
    region     = module.context.state.region
    kms_key_id = module.context.state.kms_key_id
    key        = "platform-network/${local.peer_region}/region/terraform.tfstate"
    assume_role = {
      role_arn = module.context.deploy_role_arn
    }
  }

  defaults = {}
}
