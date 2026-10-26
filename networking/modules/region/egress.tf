# Central egress: one VPC per region in the networking account (shared
# segment). NAT per AZ in the public subnets; the transit gateway attachment
# in the private ones. Environment VPCs then carry no NAT of their own.
# Leaves room for AWS Network Firewall between the two (not built).

resource "aws_vpc_ipam_pool_cidr_allocation" "egress" {
  count = local.central ? 1 : 0

  ipam_pool_id   = try(local.pool_ids.shared, null)
  netmask_length = try(local.spec.egress_vpc_netmask, 24)
  description    = "${local.name_prefix}-egress"

  # Here too: a precondition runs before the body, so a region that has not
  # joined gets this message rather than a missing-argument error.
  lifecycle {
    precondition {
      condition     = local.pool_ids != null
      error_message = "${local.region} has not joined IPAM: add it to networking/environments/global/ipam.yaml regions and apply ipam first."
    }
  }
}

module "egress_vpc" {
  count = local.central ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"
  name    = "${local.name_prefix}-egress"
  cidr    = aws_vpc_ipam_pool_cidr_allocation.egress[0].cidr
  azs     = local.egress_azs

  # Fixed layout (see core-network): each subnet its own cidrsubnet() so the
  # count is known at plan. In a /24: public /26s, attachment /28s.
  public_subnets       = [for i in range(3) : cidrsubnet(aws_vpc_ipam_pool_cidr_allocation.egress[0].cidr, 2, i)]
  private_subnets      = [for i in range(3) : cidrsubnet(aws_vpc_ipam_pool_cidr_allocation.egress[0].cidr, 4, 12 + i)]
  public_subnet_names  = [for i in range(3) : "${local.name_prefix}-egress-public-${i + 1}"]
  private_subnet_names = [for i in range(3) : "${local.name_prefix}-egress-attach-${i + 1}"]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
}

resource "aws_ec2_transit_gateway_vpc_attachment" "egress" {
  count = local.central ? 1 : 0

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.egress_vpc[0].vpc_id
  subnet_ids         = module.egress_vpc[0].private_subnets

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${local.name_prefix}-egress"
  }
}

# In shared: traffic coming back from the internet is looked up there, and
# shared routes to every local VPC.
resource "aws_ec2_transit_gateway_route_table_association" "egress" {
  count = local.central ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["shared"].id
}

# Never propagated: tables reach the egress VPC only through 0.0.0.0/0.

# All three tables: the tooling VPC (shared) has no NAT in central mode either.
resource "aws_ec2_transit_gateway_route" "default" {
  for_each = local.central ? local.segments : {}

  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.key].id
}

# Replies from the NAT gateways go back to the VPCs through the transit gateway.
resource "aws_route" "egress_return" {
  count = local.central ? 1 : 0

  route_table_id         = module.egress_vpc[0].public_route_table_ids[0]
  destination_cidr_block = local.address_space
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.egress]
}
