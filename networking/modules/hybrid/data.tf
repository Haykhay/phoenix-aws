# The first hub's region unit: on-prem attaches only there.
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

# The gateway association's transit gateway attachment, to place it in shared.
data "aws_ec2_transit_gateway_dx_gateway_attachment" "this" {
  count = local.dx ? 1 : 0

  transit_gateway_id = local.first.transit_gateway_id
  dx_gateway_id      = aws_dx_gateway.this[0].id

  depends_on = [aws_dx_gateway_association.this]
}
