# The hubs' region units. The second is read only for dual_dx.
data "terraform_remote_state" "first" {
  backend = "s3"

  config = {
    bucket     = module.context.state.bucket
    region     = module.context.state.region
    kms_key_id = module.context.state.kms_key_id
    key        = "platform-network/${local.region}/region/terraform.tfstate"
  }

  defaults = {}
}

data "terraform_remote_state" "second" {
  count   = local.dual_dx ? 1 : 0
  backend = "s3"

  config = {
    bucket     = module.context.state.bucket
    region     = module.context.state.region
    kms_key_id = module.context.state.kms_key_id
    key        = "platform-network/${local.second_hub}/region/terraform.tfstate"
  }

  defaults = {}
}

# The gateway association's transit gateway attachment, to place it in shared.
data "aws_ec2_transit_gateway_dx_gateway_attachment" "first" {
  count = local.dx ? 1 : 0

  transit_gateway_id = local.first.transit_gateway_id
  dx_gateway_id      = aws_dx_gateway.first[0].id

  depends_on = [aws_dx_gateway_association.first]
}

data "aws_ec2_transit_gateway_dx_gateway_attachment" "second" {
  provider = aws.second
  count    = local.dual_dx ? 1 : 0

  transit_gateway_id = local.second.transit_gateway_id
  dx_gateway_id      = aws_dx_gateway.second[0].id

  depends_on = [aws_dx_gateway_association.second]
}
