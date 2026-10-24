# Guardrails that must hold before anything is created. Overlap between VPCs
# is IPAM's job (atomic allocation); these cover what is cheapest to catch at
# plan time.
resource "terraform_data" "validation" {
  count = local.config.enabled ? 1 : 0

  input = local.default_vpc_name

  lifecycle {
    precondition {
      condition     = length(local.vpcs) > 0
      error_message = "core-network is enabled but no VPCs are configured. Add at least one entry under spec.vpcs."
    }
    precondition {
      condition     = contains(keys(local.vpcs), local.default_vpc_name)
      error_message = "spec.default_vpc must name one of the configured VPCs (${join(", ", keys(local.vpcs))}). It is only optional when exactly one VPC is configured."
    }
    precondition {
      condition = alltrue([
        for vpc_name, vpc in local.vpcs : length(vpc.azs) == 3
      ])
      error_message = "Every VPC needs exactly 3 azs: its subnets are carved from the IPAM allocation, one per AZ."
    }
    precondition {
      condition     = length(distinct([for vpc_name, vpc in local.vpcs : vpc.name])) == length(local.vpcs)
      error_message = "Every VPC needs a unique name. Set `name` per VPC rather than in vpc_defaults, or leave it unset to derive it from the map key."
    }
  }
}

# CreatedBy is captured once and frozen: read every run it would record
# whoever last triggered a pipeline, and tag churn rolls cluster nodes.
resource "terraform_data" "vpc_created_by" {
  for_each = local.vpcs

  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_vpc_ipam_pool_cidr_allocation" "this" {
  for_each = local.vpcs

  ipam_pool_id   = each.value.ipam_pool_id != null ? each.value.ipam_pool_id : try(data.aws_vpc_ipam_pool.this[each.key].id, null)
  netmask_length = each.value.netmask
  description    = "${each.value.name} (${local.environment}, account ${data.aws_caller_identity.current.account_id})"

  # Checked here rather than in terraform_data.validation: preconditions run
  # before the body is evaluated, so a VPC without a pool gets this message
  # instead of a missing-argument error.
  lifecycle {
    precondition {
      condition     = (each.value.pool != null || each.value.ipam_pool_id != null) && length(setintersection(keys(each.value), local.literal_network_keys)) == 0
      error_message = "VPC ${each.key} needs `pool` or `ipam_pool_id` (IPAM) and no literal network keys (${join(", ", local.literal_network_keys)}): addresses come from IPAM only."
    }
  }
}

module "vpc" {
  for_each = local.vpcs

  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"
  name    = each.value.name
  cidr    = local.vpc_cidrs[each.key]
  azs     = each.value.azs

  private_subnets = local.private_subnets_all[each.key]
  public_subnets  = local.subnets[each.key].public

  # Named by role, in the same order as private_subnets (data, then platform),
  # so the console tells a data subnet from a platform one. Only the Name tag
  # depends on this: renaming is an in-place tag update, never a replacement.
  private_subnet_names = concat(
    [for index, cidr in local.subnets[each.key].data : "${each.value.name}-data-${index + 1}"],
    [for index, cidr in local.subnets[each.key].platform : "${each.value.name}-platform-${index + 1}"],
  )
  public_subnet_names = [
    for index, cidr in local.subnets[each.key].public : "${each.value.name}-public-${index + 1}"
  ]

  # AWS Load Balancer Controller subnet discovery for internet-facing load
  # balancers. The internal-elb tag goes on the EKS subnets only, which the
  # module cannot express (it tags every private subnet alike) -- see
  # aws_ec2_tag.internal_elb below.
  public_subnet_tags = each.value.enable_elb_subnet_tags ? {
    "kubernetes.io/role/elb" = "1"
  } : {}

  enable_nat_gateway                  = each.value.enable_nat_gateway
  single_nat_gateway                  = each.value.single_nat_gateway
  one_nat_gateway_per_az              = false
  create_multiple_public_route_tables = false
  enable_vpn_gateway                  = each.value.enable_vpn_gateway

  # No Name here: the module merges `tags` after each resource's own Name, so a
  # Name in it would overwrite every subnet, route table and NAT gateway with
  # the VPC's. The VPC gets its Name from `name`.
  tags = merge(local.vpc_ownership_tags[each.key], {
    Vpc         = each.key
    Environment = local.environment
    Region      = local.region
  })
}

# AWS Load Balancer Controller subnet discovery for internal load balancers:
# with no subnet carrying kubernetes.io/role/internal-elb, it treats *every*
# private subnet as a candidate and takes the lowest subnet ID per AZ, which
# can land an internal NLB in a data subnet (RDS/ElastiCache/MSK/TGW, /22s).
# Tagging the EKS subnets -- platform, or all private ones in a VPC with no
# platform subnets, the same rule core-platform uses for cluster subnets --
# confines internal load balancers to them.
#
# The VPC module tags all private subnets alike, so the tag is added here per
# subnet instead. The default provider (providers.tf) ignores this key (ignore_tags), so the
# module's aws_subnet does not try to strip it; aws_ec2_tag does not honour
# ignore_tags and keeps managing it.
resource "aws_ec2_tag" "internal_elb" {
  for_each = merge([
    for vpc_name, vpc in local.elb_tag_vpcs : {
      for index in range(local.elb_internal_subnet_count[vpc_name]) :
      "${vpc_name}/${index}" => local.elb_internal_subnet_ids[vpc_name][index]
    }
  ]...)

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_security_group" "vpc_endpoint" {
  for_each = local.endpoint_vpcs

  name_prefix = "${each.value.name}-vpc-endpoints-"
  description = "Security group for interface VPC endpoints"
  vpc_id      = module.vpc[each.key].vpc_id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc[each.key].vpc_cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.vpc_ownership_tags[each.key], {
    Name = "${each.value.name}-vpc-endpoints"
    Vpc  = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "gateway_s3" {
  for_each = local.gateway_s3_vpcs

  vpc_id            = module.vpc[each.key].vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc[each.key].private_route_table_ids

  tags = merge(local.vpc_ownership_tags[each.key], {
    Name = "${each.value.name}-s3"
    Vpc  = each.key
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id            = module.vpc[each.value.vpc_name].vpc_id
  service_name      = "com.amazonaws.${local.region}.${each.value.service}"
  vpc_endpoint_type = "Interface"
  subnet_ids = length(local.platform_subnet_ids[each.value.vpc_name]) > 0 ? (
    local.platform_subnet_ids[each.value.vpc_name]
  ) : module.vpc[each.value.vpc_name].private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoint[each.value.vpc_name].id]
  private_dns_enabled = true

  tags = merge(local.vpc_ownership_tags[each.value.vpc_name], {
    Name = "${local.vpcs[each.value.vpc_name].name}-${replace(each.value.service, ".", "-")}"
    Vpc  = each.value.vpc_name
  })
}

# The transit gateway is shared to the account once, not once per VPC.
resource "aws_ram_resource_share" "tgw" {
  provider = aws.network
  count    = local.create_tgw_share ? 1 : 0

  name                      = "${local.name_prefix}-tgw"
  allow_external_principals = true

  tags = {
    Name = "${local.name_prefix}-tgw"
  }
}

resource "aws_ram_resource_association" "tgw" {
  provider = aws.network
  count    = local.create_tgw_share ? 1 : 0

  resource_arn       = data.aws_ec2_transit_gateway.shared[0].arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

resource "aws_ram_principal_association" "tgw" {
  provider = aws.network
  count    = local.create_tgw_share ? 1 : 0

  principal          = data.aws_caller_identity.current.account_id
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.tgw_vpcs

  subnet_ids         = local.data_subnet_ids[each.key]
  transit_gateway_id = local.resolved_tgw_id[each.key]
  vpc_id             = module.vpc[each.key].vpc_id

  depends_on = [
    aws_ram_resource_association.tgw,
  ]

  lifecycle {
    precondition {
      condition     = local.network_configured
      error_message = "VPC ${each.key} enables a transit gateway feature but spec.providers.network.account_id and .state_bucket are not both set: the networking account cannot be reached."
    }
    precondition {
      condition     = local.resolved_tgw_id[each.key] != null
      error_message = "Unable to resolve a transit gateway ID for region ${local.region}. Set the VPC's tgw_id explicitly or add region support in modules/core-network/data.tf."
    }
  }

  tags = merge(local.vpc_ownership_tags[each.key], {
    Name = "${each.value.name}-tgw-attachment"
    Vpc  = each.key
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  provider = aws.network
  for_each = local.tgw_association_vpcs

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = local.resolved_tgw_route_table_id[each.key]

  lifecycle {
    precondition {
      condition     = local.resolved_tgw_route_table_id[each.key] != null
      error_message = "Unable to resolve a transit gateway route table ID for region ${local.region}. Set the VPC's tgw_route_table_id explicitly or add region support in modules/core-network/data.tf."
    }
  }
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  provider = aws.network
  for_each = local.tgw_propagation_vpcs

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = local.resolved_tgw_propagation_route_table_id[each.key]

  lifecycle {
    precondition {
      condition     = local.resolved_tgw_propagation_route_table_id[each.key] != null
      error_message = "Unable to resolve a transit gateway propagation route table ID for region ${local.region}. Set the VPC's tgw_propagation_route_table_id explicitly or add region support in modules/core-network/data.tf."
    }
  }
}

resource "aws_ec2_transit_gateway_route" "dublin_to_vpc" {
  provider = aws.network_dublin
  for_each = local.peering_route_vpcs

  destination_cidr_block         = module.vpc[each.key].vpc_cidr_block
  transit_gateway_attachment_id  = local.dublin_peering_attachment_id
  transit_gateway_route_table_id = local.dublin_hub_route_table_id

  lifecycle {
    precondition {
      condition     = local.dublin_peering_attachment_id != null
      error_message = "No Dublin peering attachment found in the ${local.region} networks state outputs. Create the peering in aws-transit-gateway or disable enable_tgw_peering_routes."
    }
    precondition {
      condition     = local.dublin_hub_route_table_id != null
      error_message = "Unable to read dublin_tgw_route_table_id from the eu-west-1 networks state."
    }
  }

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# Return routes live on the regional route table, so they are deduplicated
# across every VPC that asked for peering rather than created per VPC.
resource "aws_ec2_transit_gateway_route" "region_to_dublin" {
  provider = aws.network
  for_each = local.peering_return_cidrs

  destination_cidr_block         = each.value
  transit_gateway_attachment_id  = local.dublin_peering_attachment_id
  transit_gateway_route_table_id = local.peering_route_table_id

  lifecycle {
    precondition {
      condition     = local.dublin_peering_attachment_id != null
      error_message = "No Dublin peering attachment found in the ${local.region} networks state outputs. Create the peering in aws-transit-gateway or disable enable_tgw_peering_routes."
    }
  }
}

resource "aws_route" "tgw_routes" {
  for_each = local.tgw_routes

  route_table_id         = module.vpc[each.value.vpc_name].private_route_table_ids[each.value.route_table_index]
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = local.resolved_tgw_id[each.value.vpc_name]

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.this,
    aws_ec2_transit_gateway_route_table_association.this,
    aws_ec2_transit_gateway_route_table_propagation.this
  ]
}
