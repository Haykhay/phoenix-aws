# This region's share of each segment, from the ipam unit. The region must
# have joined (be in ipam.yaml's regions, applied) before this unit runs.
data "terraform_remote_state" "ipam" {
  backend = "s3"

  config = {
    bucket     = module.context.state.bucket
    region     = module.context.state.region
    kms_key_id = module.context.state.kms_key_id
    key        = "platform-network/global/ipam/terraform.tfstate"
  }

  defaults = {}
}

data "aws_availability_zones" "this" {
  state = "available"
}
