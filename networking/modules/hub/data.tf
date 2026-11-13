# This hub region's region unit: transit gateway, tables, shared pool.
data "terraform_remote_state" "region" {
  backend = "s3"

  config = {
    bucket     = module.context.state.bucket
    region     = module.context.state.region
    kms_key_id = module.context.state.kms_key_id
    key        = "platform-network/${local.region}/region/terraform.tfstate"
  }

  defaults = {}
}

data "aws_availability_zones" "this" {
  state = "available"
}
