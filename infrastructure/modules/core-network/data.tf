locals {
  tgw_output_prefix_by_region = {
    "eu-west-1"      = "dublin"
    "eu-central-1"   = "frankfurt"
    "ap-northeast-2" = "seoul"
    "sa-east-1"      = "sao_paulo"
  }

  tgw_output_prefix = lookup(local.tgw_output_prefix_by_region, local.region, null)

  # Networking account: owns the transit gateways and keeps their facts in its
  # own remote state. From the YAML so no account ID is hardcoded here.
  network_settings = try(local.config.providers.network, {})
  # Only the account ID is configured; the role is its deploy role
  # (module.context.role_name).
  network_account_id = try(tostring(local.network_settings.account_id), null)
  network_role_arn   = local.network_account_id == null ? null : "arn:aws:iam::${local.network_account_id}:role/${module.context.role_name}"
  network_configured = local.network_account_id != null && try(local.network_settings.state_bucket, null) != null
  network_state = {
    bucket     = try(local.network_settings.state_bucket, null)
    region     = try(local.network_settings.state_region, "eu-west-1")
    kms_key_id = try(local.network_settings.state_kms_key_id, null)
  }

  direct_tgw_id = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => try(trimspace(vpc.tgw_id), "") != "" ? trimspace(vpc.tgw_id) : null
  }

  direct_tgw_route_table_id = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => try(trimspace(vpc.tgw_route_table_id), "") != "" ? trimspace(vpc.tgw_route_table_id) : null
  }

  direct_tgw_propagation_route_table_id = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => try(trimspace(vpc.tgw_propagation_route_table_id), "") != "" ? trimspace(vpc.tgw_propagation_route_table_id) : null
  }

  # Dublin is the hub: regional transit gateways peer with it, so peering routes
  # are only ever created from another region back towards Dublin.
  peering_route_vpcs = {
    for vpc_name, vpc in local.tgw_vpcs :
    vpc_name => vpc if vpc.enable_tgw_peering_routes && local.region != "eu-west-1"
  }

  create_tgw_peering_routes = length(local.peering_route_vpcs) > 0

  read_remote_tgw_state = local.create_tgw_peering_routes || anytrue([
    for vpc_name, vpc in local.tgw_vpcs :
    local.direct_tgw_id[vpc_name] == null || local.direct_tgw_route_table_id[vpc_name] == null
  ])

  share_tgw_vpcs   = { for vpc_name, vpc in local.tgw_vpcs : vpc_name => vpc if vpc.enable_tgw_share }
  create_tgw_share = length(local.share_tgw_vpcs) > 0

  # Key naming in the Dublin peering map differs from tgw_output_prefix_by_region
  # (e.g. "saopaulo", not "sao_paulo").
  tgw_dublin_peering_key_by_region = {
    "eu-central-1"   = "frankfurt"
    "sa-east-1"      = "saopaulo"
    "ap-northeast-2" = "seoul"
  }

  # Peering attachment IDs are identical on both sides. Not every regional state
  # exports a "dublin" key (sa-east-1 does not), and Dublin's map lacks "seoul",
  # so try the regional state first, then Dublin's map keyed by region.
  dublin_peering_attachment_id = !local.create_tgw_peering_routes || local.tgw_output_prefix == null ? null : try(coalesce(
    try(data.terraform_remote_state.network[0].outputs["${local.tgw_output_prefix}_tgw_peering_attachment_ids"]["dublin"], null),
    try(data.terraform_remote_state.network_dublin[0].outputs["dublin_tgw_peering_attachment_ids"][lookup(local.tgw_dublin_peering_key_by_region, local.region, "")], null)
  ), null)

  dublin_hub_route_table_id = !local.create_tgw_peering_routes ? null : try(
    data.terraform_remote_state.network_dublin[0].outputs["dublin_tgw_route_table_id"],
    null
  )

  remote_tgw_id = !local.read_remote_tgw_state || local.tgw_output_prefix == null ? null : (
    try(trimspace(data.terraform_remote_state.network[0].outputs["${local.tgw_output_prefix}_tgw_id"]), "") != "" ? trimspace(data.terraform_remote_state.network[0].outputs["${local.tgw_output_prefix}_tgw_id"]) : null
  )

  remote_tgw_route_table_id = !local.read_remote_tgw_state || local.tgw_output_prefix == null ? null : (
    try(trimspace(data.terraform_remote_state.network[0].outputs["${local.tgw_output_prefix}_tgw_route_table_id"]), "") != "" ? trimspace(data.terraform_remote_state.network[0].outputs["${local.tgw_output_prefix}_tgw_route_table_id"]) : null
  )

  # One transit gateway serves the whole region; per-VPC overrides exist so a
  # single VPC can be pinned to a different one without moving the others.
  resolved_tgw_id = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => try(coalesce(local.direct_tgw_id[vpc_name], local.remote_tgw_id), null)
  }

  resolved_tgw_route_table_id = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => try(coalesce(local.direct_tgw_route_table_id[vpc_name], local.remote_tgw_route_table_id), null)
  }

  resolved_tgw_propagation_route_table_id = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => try(coalesce(
      local.direct_tgw_propagation_route_table_id[vpc_name],
      local.direct_tgw_route_table_id[vpc_name],
      local.remote_tgw_route_table_id,
    ), null)
  }

  # Account/region-level resources pick the transit gateway of the first VPC
  # that asked for them; keys() is sorted, so the choice is stable.
  share_tgw_id = local.create_tgw_share ? local.resolved_tgw_id[keys(local.share_tgw_vpcs)[0]] : null

  peering_route_table_id = local.create_tgw_peering_routes ? local.resolved_tgw_route_table_id[keys(local.peering_route_vpcs)[0]] : null

  # Return routes are per regional route table, not per VPC: deduplicate the
  # CIDRs every peering-enabled VPC asked for.
  peering_return_cidrs = toset(flatten([
    for vpc_name, vpc in local.peering_route_vpcs : vpc.tgw_peering_return_cidrs
  ]))
}

data "aws_caller_identity" "current" {}

data "aws_vpc_ipam_pool" "this" {
  for_each = { for vpc_name, vpc in local.vpcs : vpc_name => vpc if vpc.ipam_pool_id == null && vpc.pool != null }

  filter {
    name   = "description"
    values = ["${each.value.pool}/${local.region}"]
  }
  filter {
    name   = "locale"
    values = [local.region]
  }
  filter {
    name   = "address-family"
    values = ["ipv4"]
  }
}

data "aws_ec2_transit_gateway" "shared" {
  provider = aws.network
  count    = local.create_tgw_share ? 1 : 0

  id = local.share_tgw_id
}

data "terraform_remote_state" "network" {
  count   = local.read_remote_tgw_state && local.network_configured ? 1 : 0
  backend = "s3"

  config = {
    bucket     = local.network_state.bucket
    key        = "${local.region}/terraform.tfstate"
    region     = local.network_state.region
    encrypt    = true
    kms_key_id = local.network_state.kms_key_id
    assume_role = {
      role_arn = local.network_role_arn
    }
  }
}

data "terraform_remote_state" "network_dublin" {
  count   = local.create_tgw_peering_routes && local.network_configured ? 1 : 0
  backend = "s3"

  config = {
    bucket     = local.network_state.bucket
    key        = "eu-west-1/terraform.tfstate"
    region     = local.network_state.region
    encrypt    = true
    kms_key_id = local.network_state.kms_key_id
    assume_role = {
      role_arn = local.network_role_arn
    }
  }
}
