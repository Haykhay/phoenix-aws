# DNS VPC (shared segment), in every region when dns_forwarding is set: the
# region's outbound Resolver endpoint and rules; in a hub region also the
# inbound endpoint on-prem forwards to. Two private subnets, nothing public.
resource "aws_vpc_ipam_pool_cidr_allocation" "dns" {
  ipam_pool_id   = try(local.region_state.pool_ids.shared, null)
  netmask_length = try(local.spec.dns_vpc_netmask, 24)
  description    = "${local.name_prefix}-dns"

  # A precondition runs before the body: a hub region without its region
  # unit gets this message rather than a missing-argument error.
  lifecycle {
    precondition {
      condition     = local.ready
      error_message = "Apply the region unit in ${local.region} before the hub unit."
    }
    precondition {
      condition     = local.is_hub || local.forward
      error_message = "${local.region} is not a hub region: the unit only forwards there, so it needs spec.network.dns_forwarding."
    }
  }
}

module "dns_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"
  name    = "${local.name_prefix}-dns"
  cidr    = aws_vpc_ipam_pool_cidr_allocation.dns.cidr
  azs     = local.dns_azs

  private_subnets      = [for i in range(2) : cidrsubnet(aws_vpc_ipam_pool_cidr_allocation.dns.cidr, 2, i)]
  private_subnet_names = [for i in range(2) : "${local.name_prefix}-dns-${i + 1}"]

  # No NAT here; this only collapses the module's per-subnet private route
  # tables into one, so both subnets get the transit gateway routes below.
  single_nat_gateway = true
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dns" {
  transit_gateway_id = local.region_state.transit_gateway_id
  vpc_id             = module.dns_vpc.vpc_id
  subnet_ids         = module.dns_vpc.private_subnets

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${local.name_prefix}-dns"
  }
}

# Shared: reached from both segments and on-prem, reaches all of them.
resource "aws_ec2_transit_gateway_route_table_association" "dns" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dns.id
  transit_gateway_route_table_id = local.region_state.route_table_ids.shared
}

resource "aws_ec2_transit_gateway_route_table_propagation" "dns" {
  for_each = local.network.segments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dns.id
  transit_gateway_route_table_id = local.region_state.route_table_ids[each.key]
}

resource "aws_route" "dns_to_tgw" {
  for_each = toset(local.dns_clients)

  route_table_id         = module.dns_vpc.private_route_table_ids[0]
  destination_cidr_block = each.value
  transit_gateway_id     = local.region_state.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dns]
}

resource "aws_security_group" "resolver" {
  name        = "${local.name_prefix}-resolver"
  description = "Route 53 Resolver endpoints: DNS from the platform and on-prem"
  vpc_id      = module.dns_vpc.vpc_id

  tags = {
    Name = "${local.name_prefix}-resolver"
  }
}

resource "aws_vpc_security_group_ingress_rule" "dns" {
  for_each = { for pair in setproduct(local.dns_clients, ["tcp", "udp"]) : "${pair[0]}/${pair[1]}" => pair }

  security_group_id = aws_security_group.resolver.id
  cidr_ipv4         = each.value[0]
  ip_protocol       = each.value[1]
  from_port         = 53
  to_port           = 53
}

# The outbound endpoint queries on-prem resolvers.
resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each = { for pair in setproduct(local.dns_clients, ["tcp", "udp"]) : "${pair[0]}/${pair[1]}" => pair }

  security_group_id = aws_security_group.resolver.id
  cidr_ipv4         = each.value[0]
  ip_protocol       = each.value[1]
  from_port         = 53
  to_port           = 53
}

# On-prem forwards the platform's zones here (hub regions only).
resource "aws_route53_resolver_endpoint" "inbound" {
  count = local.is_hub ? 1 : 0

  name               = "${local.name_prefix}-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver.id]

  dynamic "ip_address" {
    for_each = module.dns_vpc.private_subnets
    content {
      subnet_id = ip_address.value
    }
  }
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = local.forward ? 1 : 0

  name               = "${local.name_prefix}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver.id]

  dynamic "ip_address" {
    for_each = module.dns_vpc.private_subnets
    content {
      subnet_id = ip_address.value
    }
  }
}

resource "aws_route53_resolver_rule" "forward" {
  for_each = local.forwarding

  name                 = "${local.name_prefix}-${replace(each.key, ".", "-")}"
  domain_name          = each.key
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = each.value
    content {
      ip = target_ip.value
    }
  }
}

# core-network associates every rule shared with its account with each VPC.
resource "aws_ram_resource_share" "rules" {
  count = local.forward ? 1 : 0

  name                      = "${local.name_prefix}-resolver-rules"
  allow_external_principals = false

  tags = {
    Name = "${local.name_prefix}-resolver-rules"
  }
}

resource "aws_ram_resource_association" "rules" {
  for_each = local.forwarding

  resource_arn       = aws_route53_resolver_rule.forward[each.key].arn
  resource_share_arn = aws_ram_resource_share.rules[0].arn
}

resource "aws_ram_principal_association" "rules" {
  for_each = local.forward ? toset(local.network.share_with) : toset([])

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.rules[0].arn
}
