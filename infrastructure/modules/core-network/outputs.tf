locals {
  networks = {
    for vpc_name, vpc in local.vpcs : vpc_name => {
      name                = vpc.name
      segment             = vpc.segment
      vpc_id              = module.vpc[vpc_name].vpc_id
      vpc_cidr_block      = module.vpc[vpc_name].vpc_cidr_block
      azs                 = vpc.azs
      private_subnet_ids  = module.vpc[vpc_name].private_subnets
      data_subnet_ids     = local.data_subnet_ids[vpc_name]
      platform_subnet_ids = local.platform_subnet_ids[vpc_name]
      public_subnet_ids   = module.vpc[vpc_name].public_subnets

      private_subnet_cidrs  = local.private_subnets_all[vpc_name]
      data_subnet_cidrs     = local.subnets[vpc_name].data
      platform_subnet_cidrs = local.subnets[vpc_name].platform
      public_subnet_cidrs   = local.subnets[vpc_name].public

      private_route_table_ids = module.vpc[vpc_name].private_route_table_ids
      public_route_table_ids  = module.vpc[vpc_name].public_route_table_ids

      vpc_endpoint_security_group_id = try(aws_security_group.vpc_endpoint[vpc_name].id, null)
      vpc_endpoint_ids = merge(
        try({ s3 = aws_vpc_endpoint.gateway_s3[vpc_name].id }, {}),
        {
          for key, endpoint in local.interface_endpoints :
          endpoint.service => aws_vpc_endpoint.interface[key].id
          if endpoint.vpc_name == vpc_name
        }
      )

      tgw_attachment_id = try(aws_ec2_transit_gateway_vpc_attachment.this[vpc_name].id, null)
    }
  }

  # Backing values for the deprecated flat outputs below.
  default_network = try(local.networks[local.default_vpc_name], null)
}

# The contract downstream resource sets consume: every VPC in the environment,
# keyed by name, plus which one to bind to when none is named.
output "networks" {
  description = "All VPCs in this environment/region, keyed by VPC name."
  value       = local.networks
}

output "default_vpc_name" {
  description = "VPC that resource sets bind to unless they set `vpc` explicitly."
  value       = local.config.enabled ? local.default_vpc_name : null
}

output "vpc_names" {
  description = "Names of every configured VPC."
  value       = sort(keys(local.vpcs))
}

# model-cache keeps FSx through teardowns only inside a VPC that survives them.
output "long_live" {
  description = "Whether this environment's network is LongLive (survives weekend teardowns)."
  value       = try(module.context.config.tags.LongLive, false) == true
}

output "name_prefix" {
  description = "Naming prefix for account/region-level network resources."
  value       = local.name_prefix
}

# ---------------------------------------------------------------------------
# Deprecated: single-VPC outputs, resolved against the default VPC.
#
# Kept so a consumer can be rolled back to the pre-multi-VPC contract without
# also rolling back this module. Remove once the follow-up changes have landed and
# nothing reads them.
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "Default VPC: ID."
  value       = try(local.default_network.vpc_id, null)
}

output "vpc_cidr_block" {
  description = "Default VPC: CIDR block (from IPAM)."
  value       = try(local.default_network.vpc_cidr_block, null)
}

output "private_subnets" {
  description = "Default VPC: private subnet IDs."
  value       = try(local.default_network.private_subnet_ids, [])
}

output "data_subnet_ids" {
  description = "Default VPC: data subnet IDs (databases)."
  value       = try(local.default_network.data_subnet_ids, [])
}

output "platform_subnet_ids" {
  description = "Default VPC: platform subnet IDs (EKS nodes)."
  value       = try(local.default_network.platform_subnet_ids, [])
}

output "public_subnets" {
  description = "Default VPC: public subnet IDs."
  value       = try(local.default_network.public_subnet_ids, [])
}

output "private_subnet_cidrs" {
  description = "Default VPC: private subnet CIDRs."
  value       = try(local.default_network.private_subnet_cidrs, [])
}

output "public_subnet_cidrs" {
  description = "Default VPC: public subnet CIDRs."
  value       = try(local.default_network.public_subnet_cidrs, [])
}

output "private_route_table_ids" {
  description = "Default VPC: private route table IDs."
  value       = try(local.default_network.private_route_table_ids, [])
}

output "vpc_endpoint_security_group_id" {
  description = "Default VPC: security group on its interface endpoints."
  value       = try(local.default_network.vpc_endpoint_security_group_id, null)
}

output "vpc_endpoint_ids" {
  description = "Default VPC: interface endpoint IDs, by service."
  value       = try(local.default_network.vpc_endpoint_ids, {})
}

output "tgw_attachment_id" {
  description = "Default VPC: transit gateway attachment ID, if attached."
  value       = try(local.default_network.tgw_attachment_id, null)
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    resource_set = "core-network"
    default_vpc  = local.config.enabled ? local.default_vpc_name : null
    vpc_count    = length(local.vpcs)
    vpcs = {
      for vpc_name, vpc in local.vpcs : vpc_name => {
        cidr                     = module.vpc[vpc_name].vpc_cidr_block
        segment                  = vpc.segment
        private_subnet_count     = length(local.private_subnets_all[vpc_name])
        public_subnet_count      = length(local.subnets[vpc_name].public)
        platform_subnet_count    = length(local.subnets[vpc_name].platform)
        enable_vpc_endpoints     = vpc.enable_vpc_endpoints
        enable_nat_gateway       = vpc.enable_nat_gateway
        enable_tgw_attachment    = vpc.enable_tgw_attachment
        interface_endpoint_count = length([for key, endpoint in local.interface_endpoints : key if endpoint.vpc_name == vpc_name])
      }
    }
  }
}
